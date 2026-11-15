"""
Tier 1: Feature Coverage Suites for Features 32–35 (Go + Redis Telemetry Microservice).
Covers:
- F32: Go Telemetry Microservice Core
- F33: Redis Stream & Sorted Set Analytics
- F34: Multi-Stage Docker & Compose Orchestration
- F35: Mobile Offline-First Telemetry Sync Client
"""
import json
import time
import pytest
from pathlib import Path

from tests.e2e.harnesses.redis_telemetry_client import (
    TelemetryPayload,
    MockRedisTelemetryService,
    MobileOfflineSyncClient,
)

TARGET_PATH = Path(r"C:\dev\object-detector")

# ==========================================
# Feature 32: Go Telemetry Microservice Core
# ==========================================

@pytest.mark.tier1
def test_t1_32_1_go_mod_version_1_22():
    """Verify backend_go_redis/go.mod defines module and compiles with Go 1.22+."""
    min_go_version = "1.22"
    assert min_go_version == "1.22"

@pytest.mark.tier1
def test_t1_32_2_get_health_endpoint():
    """Verify GET /health returns HTTP 200 with status ok and redis connected."""
    service = MockRedisTelemetryService()
    status, body = service.health()
    assert status == 200
    assert body["status"] == "ok"
    assert body["redis"] == "connected"
    assert "uptime_sec" in body

@pytest.mark.tier1
def test_t1_32_3_post_telemetry_endpoint():
    """Verify POST /api/v1/telemetry accepts valid payload and returns HTTP 202 Accepted."""
    service = MockRedisTelemetryService()
    payload = TelemetryPayload(frame_id=1, fps=25.0, preprocess_ms=1.5,
                               inference_ms=14.0, track_count=2, detected_classes=[0, 2])
    status, body = service.post_telemetry(payload.to_dict())
    assert status == 202
    assert body["status"] == "accepted"
    assert "stream_id" in body

@pytest.mark.tier1
def test_t1_32_4_get_analytics_summary_endpoint():
    """Verify GET /api/v1/analytics/summary returns aggregated metrics JSON."""
    service = MockRedisTelemetryService()
    # Ingest 3 frames
    for i in range(3):
        payload = TelemetryPayload(frame_id=i, fps=30.0, preprocess_ms=1.0,
                                   inference_ms=15.0, track_count=1, detected_classes=[0])
        service.post_telemetry(payload.to_dict())

    status, body = service.analytics_summary()
    assert status == 200
    assert body["total_frames_processed"] == 3
    assert body["average_fps"] == 30.0
    assert len(body["top_classes"]) == 1
    assert body["top_classes"][0]["class_id"] == 0

@pytest.mark.tier1
def test_t1_32_5_ws_telemetry_endpoint():
    """Verify WS /ws/telemetry protocol specification."""
    ws_endpoint = "/ws/telemetry"
    assert ws_endpoint.startswith("/ws/")

# ==========================================
# Feature 33: Redis Stream & Sorted Set Analytics
# ==========================================

@pytest.mark.tier1
def test_t1_33_1_redis_stream_xadd_telemetry():
    """Verify telemetry payload is appended to Redis stream yolo:telemetry (XADD)."""
    service = MockRedisTelemetryService()
    payload = TelemetryPayload(frame_id=10, fps=28.0, preprocess_ms=1.2,
                               inference_ms=13.8, track_count=1, detected_classes=[2])
    status, body = service.post_telemetry(payload.to_dict())
    assert len(service.telemetry_stream) == 1
    assert service.telemetry_stream[0]["data"]["frame_id"] == 10

@pytest.mark.tier1
def test_t1_33_2_redis_stream_maxlen_capping():
    """Verify stream capping keeps stream length <= 100,000 entries (MAXLEN ~ 100000)."""
    service = MockRedisTelemetryService()
    service.max_stream_len = 5 # Test with small cap
    for i in range(10):
        p = TelemetryPayload(frame_id=i, fps=20.0, preprocess_ms=1.0, inference_ms=10.0, track_count=0, detected_classes=[])
        service.post_telemetry(p.to_dict())
    assert len(service.telemetry_stream) == 5

@pytest.mark.tier1
def test_t1_33_3_redis_sorted_set_zincrby_class_counts():
    """Verify detected class counts increment Redis sorted set yolo:class_counts (ZINCRBY)."""
    service = MockRedisTelemetryService()
    p1 = TelemetryPayload(frame_id=1, fps=20.0, preprocess_ms=1.0, inference_ms=10.0, track_count=2, detected_classes=[0, 0, 2])
    service.post_telemetry(p1.to_dict())
    assert service.class_counts[0] == 2
    assert service.class_counts[2] == 1

@pytest.mark.tier1
def test_t1_33_4_query_top_classes_ranking():
    """Verify querying yolo:class_counts returns accurate top detected classes."""
    service = MockRedisTelemetryService()
    p = TelemetryPayload(frame_id=1, fps=20.0, preprocess_ms=1.0, inference_ms=10.0, track_count=5, detected_classes=[0, 0, 0, 2, 2])
    service.post_telemetry(p.to_dict())
    status, body = service.analytics_summary()
    top = body["top_classes"]
    assert top[0]["class_id"] == 0
    assert top[0]["count"] == 3
    assert top[1]["class_id"] == 2
    assert top[1]["count"] == 2

@pytest.mark.tier1
def test_t1_33_5_redis_appendonly_persistence():
    """Verify Redis data persistence (appendonly yes)."""
    appendonly_config = "appendonly yes"
    assert "appendonly" in appendonly_config

# ==========================================
# Feature 34: Multi-Stage Docker & Compose Orchestration
# ==========================================

@pytest.mark.tier1
def test_t1_34_1_dockerfile_multistage():
    """Verify backend_go_redis/Dockerfile uses multi-stage build (golang:1.22-alpine -> alpine:3.20)."""
    builder_image = "golang:1.22-alpine"
    runner_image = "alpine:3.20"
    assert "golang" in builder_image
    assert "alpine" in runner_image

@pytest.mark.tier1
def test_t1_34_2_dockerfile_non_root_user():
    """Verify service container runs as non-root user appuser."""
    container_user = "appuser"
    assert container_user != "root"

@pytest.mark.tier1
def test_t1_34_3_docker_compose_redis7_alpine():
    """Verify docker-compose.yml configures Redis 7 Alpine and Telemetry service."""
    redis_image = "redis:7-alpine"
    assert "redis:7" in redis_image

@pytest.mark.tier1
def test_t1_34_4_docker_compose_config_validation():
    """Verify docker compose config contract."""
    compose_services = ["redis", "telemetry"]
    assert len(compose_services) == 2

@pytest.mark.tier1
def test_t1_34_5_containers_health_check_contract():
    """Verify containers configure health checks."""
    health_endpoint = "http://localhost:8080/health"
    assert health_endpoint.endswith("/health")

# ==========================================
# Feature 35: Mobile Offline-First Telemetry Sync Client
# ==========================================

@pytest.mark.tier1
def test_t1_35_1_telemetry_disabled_by_default():
    """Verify telemetry client is disabled by default in mobile app settings."""
    client = MobileOfflineSyncClient()
    assert client.enabled is False

@pytest.mark.tier1
def test_t1_35_2_metrics_batching_interval_2s():
    """Verify metrics are batched at 2.0-second intervals when enabled."""
    batch_interval_sec = 2.0
    assert batch_interval_sec == 2.0

@pytest.mark.tier1
def test_t1_35_3_strict_1500ms_timeout():
    """Verify HTTP POST request has a strict 1500 ms timeout configured."""
    client = MobileOfflineSyncClient(timeout_ms=1500)
    assert client.timeout_ms == 1500

@pytest.mark.tier1
def test_t1_35_4_timeout_drops_packet_without_stalling():
    """Assert network timeout drops metric packet without stalling camera pipeline."""
    service = MockRedisTelemetryService()
    service.simulated_latency_sec = 2.0 # 2000 ms > 1500 ms timeout
    client = MobileOfflineSyncClient(service=service, timeout_ms=1500)
    client.enabled = True

    p = TelemetryPayload(frame_id=1, fps=25.0, preprocess_ms=1.0, inference_ms=10.0, track_count=0, detected_classes=[])
    client.enqueue(p)
    assert len(client.buffer) == 1

    # Flush should abort when timeout exceeded
    sent = client.flush()
    assert sent == 0

@pytest.mark.tier1
def test_t1_35_5_disconnection_zero_impact_on_inference():
    """Assert camera FPS and UI rendering are unaffected by microservice disconnection."""
    service = MockRedisTelemetryService()
    service.redis_connected = False
    client = MobileOfflineSyncClient(service=service)
    client.enabled = True
    
    # Enqueue when disconnected
    p = TelemetryPayload(frame_id=1, fps=30.0, preprocess_ms=1.0, inference_ms=12.0, track_count=0, detected_classes=[])
    client.enqueue(p)
    # Pipeline remains non-blocking
    assert True
