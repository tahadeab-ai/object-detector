package main

import (
	"bytes"
	"encoding/json"
	"io"
	"net/http/httptest"
	"testing"
)

func TestHealthCheckEndpoint(t *testing.T) {
	hub := newTelemetryHub()
	go hub.run()
	app := setupApp(nil, hub)

	req := httptest.NewRequest("GET", "/health", nil)
	resp, err := app.Test(req)
	if err != nil {
		t.Fatalf("Failed to execute request: %v", err)
	}

	if resp.StatusCode != 200 {
		t.Fatalf("Expected status code 200, got %d", resp.StatusCode)
	}

	body, _ := io.ReadAll(resp.Body)
	var result map[string]interface{}
	if err := json.Unmarshal(body, &result); err != nil {
		t.Fatalf("Failed to parse JSON response: %v", err)
	}

	if result["status"] != "healthy" {
		t.Errorf("Expected status 'healthy', got '%v'", result["status"])
	}
}

func TestTelemetryIngestionEndpoint(t *testing.T) {
	hub := newTelemetryHub()
	go hub.run()
	app := setupApp(nil, hub)

	payload := FrameTelemetryPayload{
		FrameID:        101,
		Timestamp:      1700000000000,
		FPS:            28.5,
		InferenceMS:    34.2,
		TrackerMS:      1.2,
		TotalLatencyMS: 35.4,
		Backend:        "Vulkan Compute",
		TracksCount:    1,
		Detections: []DetectionPayload{
			{
				TrackID:    1,
				ClassID:    0,
				Confidence: 0.95,
				State:      "confirmed",
				Zone:       "center",
				Proximity:  "near",
				BBox:       []float64{0.2, 0.3, 0.5, 0.8},
			},
		},
	}

	rawBytes, _ := json.Marshal(payload)
	req := httptest.NewRequest("POST", "/api/telemetry", bytes.NewReader(rawBytes))
	req.Header.Set("Content-Type", "application/json")

	resp, err := app.Test(req)
	if err != nil {
		t.Fatalf("Failed to execute telemetry POST: %v", err)
	}

	if resp.StatusCode != 200 {
		t.Fatalf("Expected status code 200, got %d", resp.StatusCode)
	}

	body, _ := io.ReadAll(resp.Body)
	var result map[string]interface{}
	if err := json.Unmarshal(body, &result); err != nil {
		t.Fatalf("Failed to parse JSON response: %v", err)
	}

	if result["status"] != "received" {
		t.Errorf("Expected status 'received', got '%v'", result["status"])
	}
	if int(result["frame_id"].(float64)) != 101 {
		t.Errorf("Expected frame_id 101, got %v", result["frame_id"])
	}
}
