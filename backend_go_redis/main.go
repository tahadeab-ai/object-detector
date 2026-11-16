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
	FrameID        int                `json:"frame_id"`
	Timestamp      int64              `json:"timestamp"`
	FPS            float64            `json:"fps"`
	InferenceMS    float64            `json:"inference_ms"`
	TrackerMS      float64            `json:"tracker_ms"`
	TotalLatencyMS float64            `json:"total_latency_ms"`
	Backend        string             `json:"backend"`
	TracksCount    int                `json:"tracks_count"`
	Detections     []DetectionPayload `json:"detections"`
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

	// Healthcheck endpoint
	app.Get("/health", func(c *fiber.Ctx) error {
		return c.JSON(fiber.Map{
			"status":    "healthy",
			"timestamp": time.Now().UTC().Format(time.RFC3339),
			"service":   "yolo-telemetry",
		})
	})

	// Telemetry ingestion endpoint from mobile client
	app.Post("/api/telemetry", func(c *fiber.Ctx) error {
		var payload FrameTelemetryPayload
		if err := c.BodyParser(&payload); err != nil {
			return c.Status(fiber.StatusBadRequest).JSON(fiber.Map{
				"error": fiber.Map{
					"code":    "INVALID_PAYLOAD",
					"message": err.Error(),
				},
			})
		}

		rawBytes, _ := json.Marshal(payload)

		// Broadcast to connected WebSocket clients
		select {
		case hub.broadcast <- rawBytes:
		default:
		}

		// Push to Redis Streams if Redis is connected
		if rdb != nil {
			ctx, cancel := context.WithTimeout(context.Background(), 200*time.Millisecond)
			defer cancel()

			_ = rdb.XAdd(ctx, &redis.XAddArgs{
				Stream: "yolo:telemetry",
				Values: map[string]interface{}{
					"frame_id":  payload.FrameID,
					"fps":       payload.FPS,
					"latency":   payload.TotalLatencyMS,
					"tracks":    payload.TracksCount,
					"payload":   string(rawBytes),
					"timestamp": payload.Timestamp,
				},
			}).Err()

			// Increment class counts in Redis Sorted Set
			for _, det := range payload.Detections {
				_ = rdb.ZIncrBy(ctx, "yolo:class_counts", 1.0, fmt.Sprintf("%d", det.ClassID)).Err()
			}
		}

		return c.Status(fiber.StatusOK).JSON(fiber.Map{
			"status":   "received",
			"frame_id": payload.FrameID,
		})
	})

	// WebSocket streaming endpoint for web dashboards
	app.Use("/ws", func(c *fiber.Ctx) error {
		if websocket.IsWebSocketUpgrade(c) {
			return c.Next()
		}
		return fiber.ErrUpgradeRequired
	})

	app.Get("/ws", websocket.New(func(c *websocket.Conn) {
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
