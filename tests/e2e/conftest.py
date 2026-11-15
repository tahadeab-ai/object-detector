"""
Pytest root configuration and fixtures for YOLO NCNN Detector E2E test suite.
"""
import os
import shutil
import subprocess
import pytest
from pathlib import Path

REPO_ROOT = Path(r"C:\dev\object-detector")
FIXTURES_DIR = REPO_ROOT / "tests" / "e2e" / "fixtures"

@pytest.fixture(scope="session")
def repo_root() -> Path:
    return REPO_ROOT

@pytest.fixture(scope="session")
def fixtures_dir() -> Path:
    return FIXTURES_DIR

@pytest.fixture(scope="session")
def valid_tensor_path() -> Path:
    return FIXTURES_DIR / "tensors" / "valid_output_1_84_8400.bin"

@pytest.fixture(scope="session")
def corrupted_tensor_path() -> Path:
    return FIXTURES_DIR / "tensors" / "corrupted_nan_inf.bin"

@pytest.fixture(scope="session")
def empty_tensor_path() -> Path:
    return FIXTURES_DIR / "tensors" / "empty_zero_tensor.bin"

@pytest.fixture(scope="session")
def malformed_tensor_path() -> Path:
    return FIXTURES_DIR / "tensors" / "malformed_shape_80_8400.bin"

@pytest.fixture(scope="session")
def valid_metadata_path() -> Path:
    return FIXTURES_DIR / "metadata" / "valid_model_metadata.json"

@pytest.fixture(scope="session")
def invalid_blob_metadata_path() -> Path:
    return FIXTURES_DIR / "metadata" / "invalid_blob_metadata.json"

@pytest.fixture(scope="session")
def corrupted_dims_metadata_path() -> Path:
    return FIXTURES_DIR / "metadata" / "corrupted_dims_metadata.json"

@pytest.fixture(scope="session")
def coco_labels_path() -> Path:
    return FIXTURES_DIR / "labels" / "valid_coco80_labels.json"

@pytest.fixture(scope="session")
def sample_images() -> dict:
    img_dir = FIXTURES_DIR / "images"
    return {
        "street": img_dir / "test_street.jpg",
        "workspace": img_dir / "test_workspace.jpg",
        "retail": img_dir / "test_retail.jpg"
    }

@pytest.fixture
def fresh_tracker():
    from tests.e2e.harnesses.reference_engine import TwoStageTracker
    return TwoStageTracker()

@pytest.fixture(scope="session")
def environment_info() -> dict:
    info = {
        "os": os.name,
        "platform": sys_platform(),
        "has_cargo": shutil.which("cargo") is not None,
        "has_rustc": shutil.which("rustc") is not None,
        "has_go": shutil.which("go") is not None,
        "has_flutter": shutil.which("flutter") is not None,
        "has_adb": shutil.which("adb") is not None,
        "has_cmake": shutil.which("cmake") is not None,
    }
    return info

def sys_platform() -> str:
    import platform
    return platform.platform()

def pytest_configure(config):
    config.addinivalue_line("markers", "tier1: mark test as Tier 1 Feature Coverage")
    config.addinivalue_line("markers", "tier2: mark test as Tier 2 Boundary / Corner Case")
    config.addinivalue_line("markers", "tier3: mark test as Tier 3 Pairwise / Combinatorial Interaction")
    config.addinivalue_line("markers", "tier4: mark test as Tier 4 Real-World Application Scenario")
