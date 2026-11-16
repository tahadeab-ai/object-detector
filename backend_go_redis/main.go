package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"os"
	"sync"
	"time"

	"github.com/gofiber/contrib/websocket"
	"github.com/gofiber/fiber/v2"
	"github.com/gofiber/fiber/v2/middleware/cors"
	"github.com/redis/go-redis/v9"
)

var startTime = time.Now()

// DetectionPayload represents a single detected object in the frame
type DetectionPayload struct {
	TrackID    int       `json:"track_id"`
	ClassID    int       `json:"class_id"`
	Confidence float64   `json:"confidence"`
	State      string    `json:"state"`
	Zone       string    `json:"zone"`
	Proximity  string    `json:"proximity"`
	BBox       []float64 `json:"bbox"` // [x1, y1, x2, y2]
}

// FrameTelemetryPayload represents the complete frame event received from mobile app
type FrameTelemetryPayload struct {
	FrameID        int                `json:"frame_id,omitempty"`
	Timestamp      int64              `json:"timestamp,omitempty"`
	FPS            float64            `json:"fps"`
	InferenceMS    float64            `json:"inference_ms"`
	TrackerMS      float64            `json:"tracker_ms,omitempty"`
	TotalLatencyMS float64            `json:"total_latency_ms,omitempty"`
	Backend        string             `json:"backend"`
	TracksCount    int                `json:"tracks_count,omitempty"`
	Detections     []DetectionPayload `json:"detections,omitempty"`
}

// BatchTelemetryRequest represents the batched JSON payload per P4.1
type BatchTelemetryRequest struct {
	DeviceModel     string                  `json:"device_model"`
	Backend         string                  `json:"backend"`
	FPS             float64                 `json:"fps"`
	InferenceMS     float64                 `json:"inference_ms"`
	DetectedClasses []int                   `json:"detected_classes"`
	Frames          []FrameTelemetryPayload `json:"frames,omitempty"`
}

// TelemetryHub manages WebSocket client connections and live broadcasts
type TelemetryHub struct {
	clients    map[*websocket.Conn]bool
	broadcast  chan []byte
	register   chan *websocket.Conn
	unregister chan *websocket.Conn
	mu         sync.RWMutex
}

func newTelemetryHub() *TelemetryHub {
	return &TelemetryHub{
		clients:    make(map[*websocket.Conn]bool),
		broadcast:  make(chan []byte, 256),
		register:   make(chan *websocket.Conn),
		unregister: make(chan *websocket.Conn),
	}
}

func (h *TelemetryHub) run() {
	for {
		select {
		case conn := <-h.register:
			h.mu.Lock()
			h.clients[conn] = true
			h.mu.Unlock()
		case conn := <-h.unregister:
			h.mu.Lock()
			if _, ok := h.clients[conn]; ok {
				delete(h.clients, conn)
				conn.Close()
			}
			h.mu.Unlock()
		case message := <-h.broadcast:
			h.mu.RLock()
			for conn := range h.clients {
				if err := conn.WriteMessage(websocket.TextMessage, message); err != nil {
					conn.Close()
					delete(h.clients, conn)
				}
			}
			h.mu.RUnlock()
		}
	}
}

func setupApp(rdb *redis.Client, hub *TelemetryHub) *fiber.App {
	app := fiber.New(fiber.Config{
		AppName: "YOLO NCNN Telemetry Service v1.0",
	})

	app.Use(cors.New())

	// 1. GET /health (Redis ping + uptime)
	app.Get("/health", func(c *fiber.Ctx) error {
		uptime := time.Since(startTime).Truncate(time.Second).String()
		redisStatus := "disconnected"

		if rdb != nil {
			ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
			defer cancel()
			if err := rdb.Ping(ctx).Err(); err == nil {
				redisStatus = "connected"
			}
		}

		return c.Status(fiber.StatusOK).JSON(fiber.Map{
			"status":    "healthy",
			"uptime":    uptime,
			"redis":     redisStatus,
			"timestamp": time.Now().UTC().Format(time.RFC3339),
			"service":   "yolo-telemetry",
		})
	})

	// 2. POST /api/v1/telemetry (batched JSON: device_model, backend, fps, inference_ms, detected_classes)
	app.Post("/api/v1/telemetry", func(c *fiber.Ctx) error {
		var payload BatchTelemetryRequest
		if err := c.BodyParser(&payload); err != nil {
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
				"error": fiber.Map{
					"code":    "INVALID_PAYLOAD",
					"message": err.Error(),
				},
			})
		}

		rawBytes, _ := json.Marshal(payload)

		// Broadcast to WebSocket clients
		select {
		case hub.broadcast <- rawBytes:
		default:
		}

		// Store in Redis Stream and Sorted Set
		if rdb != nil {
			ctx, cancel := context.WithTimeout(context.Background(), 300*time.Millisecond)
			defer cancel()

			classesJSON, _ := json.Marshal(payload.DetectedClasses)

			_ = rdb.XAdd(ctx, &redis.XAddArgs{
				Stream: "yolo:telemetry",
				Values: map[string]interface{}{
					"device_model":     payload.DeviceModel,
					"backend":          payload.Backend,
					"fps":              payload.FPS,
					"inference_ms":     payload.InferenceMS,
					"detected_classes": string(classesJSON),
					"timestamp":        time.Now().UnixMilli(),
				},
			}).Err()

			// Increment class counts in Redis Sorted Set: yolo:class_counts
			for _, classID := range payload.DetectedClasses {
				_ = rdb.ZIncrBy(ctx, "yolo:class_counts", 1.0, fmt.Sprintf("%d", classID)).Err()
			}
		}

		return c.Status(fiber.StatusOK).JSON(fiber.Map{
			"status":       "received",
			"device_model": payload.DeviceModel,
			"backend":      payload.Backend,
		})
	})

	// 3. WS /ws/telemetry
	app.Use("/ws/telemetry", func(c *fiber.Ctx) error {
		if websocket.IsWebSocketUpgrade(c) {
			return c.Next()
		}
		return fiber.ErrUpgradeRequired
	})

	app.Get("/ws/telemetry", websocket.New(func(c *websocket.Conn) {
		hub.register <- c
		defer func() {
			hub.unregister <- c
		}()

		for {
			_, _, err := c.ReadMessage()
			if err != nil {
				break
			}
		}
	}))

	// 4. GET /api/v1/analytics/summary (reading ZREVRANGEWITHSCORES yolo:class_counts 0 19 and XREVRANGE yolo:telemetry + - COUNT 50)
	app.Get("/api/v1/analytics/summary", func(c *fiber.Ctx) error {
		topClasses := []fiber.Map{}
		recentTelemetry := []fiber.Map{}

		if rdb != nil {
			ctx, cancel := context.WithTimeout(context.Background(), 400*time.Millisecond)
			defer cancel()

			// ZREVRANGEWITHSCORES yolo:class_counts 0 19
			zRes, err := rdb.ZRevRangeWithScores(ctx, "yolo:class_counts", 0, 19).Result()
			if err == nil {
				for _, z := range zRes {
					topClasses = append(topClasses, fiber.Map{
						"class_id": z.Member,
						"count":    int64(z.Score),
					})
				}
			}

			// XREVRANGE yolo:telemetry + - COUNT 50
			xRes, err := rdb.XRevRangeN(ctx, "yolo:telemetry", "+", "-", 50).Result()
			if err == nil {
				for _, msg := range xRes {
					recentTelemetry = append(recentTelemetry, fiber.Map{
						"id":     msg.ID,
						"values": msg.Values,
					})
				}
			}
		}

		return c.Status(fiber.StatusOK).JSON(fiber.Map{
			"status":           "success",
			"top_classes":      topClasses,
			"recent_telemetry": recentTelemetry,
			"timestamp":        time.Now().UTC().Format(time.RFC3339),
		})
	})

	return app
}

func main() {
	redisAddr := os.Getenv("REDIS_ADDR")
	if redisAddr == "" {
		redisAddr = "localhost:6379"
	}

	rdb := redis.NewClient(&redis.Options{
		Addr: redisAddr,
	})

	hub := newTelemetryHub()
	go hub.run()

	app := setupApp(rdb, hub)

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	log.Printf("Starting YOLO Telemetry Microservice on :%s (Redis: %s)", port, redisAddr)
	if err := app.Listen(":" + port); err != nil {
		log.Fatalf("Server shutdown error: %v", err)
	}
}
