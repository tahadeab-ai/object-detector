"""
Redis & Go Telemetry Client Harness for YOLO NCNN Detector.
Simulates and verifies REST/WebSocket communication with backend_go_redis.
Enforces offline-first buffering, 1500ms timeout limits, and schema validation.
"""
import json
import time
from typing import Dict, Any, List, Optional
from collections import deque

class PayloadDict(dict):
    """Dictionary supporting both item and attribute access."""
    def __getattr__(self, item):
        try:
            return self[item]
        except KeyError:
            raise AttributeError(item)

    def __setattr__(self, key, value):
        self[key] = value

class TelemetryPayload:
    """Represents a validated telemetry packet sent from mobile client to microservice."""
    def __init__(self, frame_id: int, fps: float, preprocess_ms: float,
                 inference_ms: float, track_count: int, detected_classes: List[int],
                 backend: str = "cpu", timestamp: Optional[float] = None):
        self.frame_id = frame_id
        self.fps = fps
        self.preprocess_ms = preprocess_ms
        self.inference_ms = inference_ms
        self.track_count = track_count
        self.detected_classes = detected_classes
        self.backend = backend
        self.timestamp = timestamp or time.time()

    def to_dict(self) -> Dict[str, Any]:
        return PayloadDict({
            "frame_id": self.frame_id,
            "fps": round(self.fps, 2),
            "preprocess_ms": round(self.preprocess_ms, 2),
            "inference_ms": round(self.inference_ms, 2),
            "track_count": self.track_count,
            "detected_classes": self.detected_classes,
            "backend": self.backend,
            "timestamp": self.timestamp
        })

    def validate(self) -> bool:
        if self.fps < 0.0 or self.fps > 240.0:
            return False
        if self.preprocess_ms < 0.0 or self.inference_ms < 0.0:
            return False
        if self.track_count < 0 or self.track_count > 100:
            return False
        if self.backend not in ("cpu", "vulkan"):
            return False
        return True

class MockRedisTelemetryService:
    """In-memory reference simulation of Go Fiber + Redis microservice."""
    def __init__(self):
        self.is_healthy = True
        self.redis_connected = True
        self.uptime_start = time.time()
        self.telemetry_stream: List[Dict[str, Any]] = [] # simulates yolo:telemetry
        self.stream_data: List[Dict[str, Any]] = []      # raw payload history for Tier 4 suites
        self.class_counts: Dict[int, int] = {}           # simulates yolo:class_counts sorted set
        self.max_stream_len = 100000
        self.simulated_latency_sec = 0.0

    def health(self) -> (int, Dict[str, Any]):
        if not self.redis_connected:
            return 503, {"status": "error", "redis": "disconnected"}
        return 200, {
            "status": "ok",
            "redis": "connected",
            "uptime_sec": int(time.time() - self.uptime_start)
        }

    def post_telemetry(self, payload_dict: Dict[str, Any]) -> (int, Dict[str, Any]):
        if not self.redis_connected:
            return 503, {"error": "Redis disconnected"}

        if self.simulated_latency_sec > 0:
            time.sleep(self.simulated_latency_sec)

        required_fields = ["frame_id", "fps", "preprocess_ms", "inference_ms", "track_count", "detected_classes"]
        for f in required_fields:
            if f not in payload_dict:
                return 422, {"error": f"Missing required field {f}"}

        # Check payload size (< 1 MB)
        serialized = json.dumps(payload_dict)
        if len(serialized.encode("utf-8")) > 1024 * 1024:
            return 413, {"error": "Payload exceeds 1MB limit"}

        # Append to stream with approximate capping
        stream_id = f"{int(time.time() * 1000)}-0"
        self.stream_data.append(payload_dict)
        self.telemetry_stream.append({"id": stream_id, "data": payload_dict})
        if len(self.telemetry_stream) > self.max_stream_len:
            self.telemetry_stream.pop(0)
        if len(self.stream_data) > self.max_stream_len:
            self.stream_data.pop(0)

        # Update sorted set yolo:class_counts
        for cls_id in payload_dict.get("detected_classes", []):
            self.class_counts[cls_id] = self.class_counts.get(cls_id, 0) + 1

        return 202, {"status": "accepted", "stream_id": stream_id}

    def analytics_summary(self) -> (int, Dict[str, Any]):
        total_frames = len(self.telemetry_stream)
        avg_fps = 0.0
        if total_frames > 0:
            avg_fps = sum(p["data"].get("fps", 0.0) for p in self.telemetry_stream) / total_frames
        
        top_classes = sorted(self.class_counts.items(), key=lambda x: x[1], reverse=True)[:5]
        return 200, {
            "total_frames_processed": total_frames,
            "average_fps": round(avg_fps, 2),
            "top_classes": [{"class_id": c[0], "count": c[1]} for c in top_classes]
        }

class MobileOfflineSyncClient:
    """Mobile client telemetry buffer with 1500ms timeout and queue capping."""
    def __init__(self, service: Optional[MockRedisTelemetryService] = None, timeout_ms: int = 1500, max_queue: int = 10):
        self.service = service
        self.timeout_ms = timeout_ms
        self.max_queue = max_queue
        self.buffer: deque = deque(maxlen=max_queue)
        self.enabled = False

    def enqueue(self, payload: TelemetryPayload) -> bool:
        if not self.enabled:
            return False
        if not payload.validate():
            return False
        self.buffer.append(payload.to_dict())
        return True

    def flush(self) -> int:
        if not self.enabled or not self.service:
            return 0
        sent = 0
        while self.buffer:
            item = self.buffer[0]
            start = time.time()
            # Strict timeout enforcement
            try:
                status, resp = self.service.post_telemetry(item)
                elapsed_ms = (time.time() - start) * 1000
                if elapsed_ms > self.timeout_ms:
                    # Timeout exceeded, abort flush
                    break
                if status == 202:
                    self.buffer.popleft()
                    sent += 1
                else:
                    break
            except Exception:
                break
        return sent
