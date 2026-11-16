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
	if result["service"] != "yolo-telemetry" {
		t.Errorf("Expected service 'yolo-telemetry', got '%v'", result["service"])
	}
}

func TestBatchedTelemetryEndpoint(t *testing.T) {
	hub := newTelemetryHub()
	go hub.run()
	app := setupApp(nil, hub)

	payload := BatchTelemetryRequest{
		DeviceModel:     "SM-N970U",
		Backend:         "Vulkan Compute",
		FPS:             24.8,
		InferenceMS:     38.2,
		DetectedClasses: []int{0, 2, 5},
	}

	rawBytes, _ := json.Marshal(payload)
	req := httptest.NewRequest("POST", "/api/v1/telemetry", bytes.NewReader(rawBytes))
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
	if result["device_model"] != "SM-N970U" {
		t.Errorf("Expected device_model 'SM-N970U', got '%v'", result["device_model"])
	}
}

func TestAnalyticsSummaryEndpoint(t *testing.T) {
	hub := newTelemetryHub()
	go hub.run()
	app := setupApp(nil, hub)

	req := httptest.NewRequest("GET", "/api/v1/analytics/summary", nil)
	resp, err := app.Test(req)
	if err != nil {
		t.Fatalf("Failed to execute summary GET: %v", err)
	}

	if resp.StatusCode != 200 {
		t.Fatalf("Expected status code 200, got %d", resp.StatusCode)
	}

	body, _ := io.ReadAll(resp.Body)
	var result map[string]interface{}
	if err := json.Unmarshal(body, &result); err != nil {
		t.Fatalf("Failed to parse JSON response: %v", err)
	}

	if result["status"] != "success" {
		t.Errorf("Expected status 'success', got '%v'", result["status"])
	}
}

func TestWebSocketUpgradeRequired(t *testing.T) {
	hub := newTelemetryHub()
	go hub.run()
	app := setupApp(nil, hub)

	req := httptest.NewRequest("GET", "/ws/telemetry", nil)
	resp, err := app.Test(req)
	if err != nil {
		t.Fatalf("Failed to execute request: %v", err)
	}

	// Normal HTTP GET without upgrade headers should return 426 Upgrade Required
	if resp.StatusCode != 426 {
		t.Errorf("Expected status code 426, got %d", resp.StatusCode)
	}
}
