#!/usr/bin/env python3
"""
Master E2E Test Runner CLI for YOLO NCNN Detector.
Authoritative orchestrator for all 4 test tiers (460 tests total):
- Tier 1: Feature Coverage (200 tests)
- Tier 2: Boundary & Corner Cases (200 tests)
- Tier 3: Cross-Feature Interactions (40 tests)
- Tier 4: Real-World Scenarios (20 tests)
"""
import sys
import os
import time
import argparse
from pathlib import Path
from typing import Dict, List, Optional

# Ensure repository root is on sys.path
SCRIPT_DIR = Path(__file__).resolve().parent
REPO_ROOT = SCRIPT_DIR.parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

import pytest

TIER_NAMES = {
    1: "Tier 1: Feature Coverage",
    2: "Tier 2: Boundary & Corner Cases",
    3: "Tier 3: Cross-Feature Interactions",
    4: "Tier 4: Real-World Scenarios",
}

TIER_DIRS = {
    1: SCRIPT_DIR / "tier1_features",
    2: SCRIPT_DIR / "tier2_boundaries",
    3: SCRIPT_DIR / "tier3_pairwise",
    4: SCRIPT_DIR / "tier4_workloads",
}

class TierResultCollector:
    """Pytest plugin to track per-tier outcomes and capture failure details."""

    def __init__(self, target_tiers: List[int]):
        self.target_tiers = target_tiers
        self.stats: Dict[int, Dict[str, int]] = {
            tier: {"total": 0, "passed": 0, "failed": 0, "skipped": 0}
            for tier in target_tiers
        }
        self.failures: List[Dict[str, str]] = []

    def pytest_runtest_logreport(self, report):
        if report.when == "call" or (report.when == "setup" and report.failed):
            tier = self._identify_tier(report.nodeid)
            if tier in self.stats:
                self.stats[tier]["total"] += 1
                if report.passed:
                    self.stats[tier]["passed"] += 1
                elif report.failed:
                    self.stats[tier]["failed"] += 1
                    self.failures.append({
                        "nodeid": report.nodeid,
                        "repr": str(report.longreprtext or report.longrepr or ""),
                    })
                elif report.skipped:
                    self.stats[tier]["skipped"] += 1

    def _identify_tier(self, nodeid: str) -> Optional[int]:
        normalized = nodeid.replace("\\", "/")
        if "tier1_features" in normalized:
            return 1
        elif "tier2_boundaries" in normalized:
            return 2
        elif "tier3_pairwise" in normalized:
            return 3
        elif "tier4_workloads" in normalized:
            return 4
        return None


def print_summary_table(collector: TierResultCollector, duration_sec: float) -> int:
    """Print clean formatted ASCII/Unicode summary report table."""
    total_count = sum(s["total"] for s in collector.stats.values())
    total_passed = sum(s["passed"] for s in collector.stats.values())
    total_failed = sum(s["failed"] for s in collector.stats.values())
    total_skipped = sum(s["skipped"] for s in collector.stats.values())
    overall_rate = (total_passed / total_count * 100.0) if total_count > 0 else 0.0

    sep_double = "=" * 80
    sep_single = "-" * 80

    print("\n" + sep_double)
    print("                      YOLO NCNN DETECTOR - E2E TEST SUITE                       ")
    print(sep_double)
    print(f" {'Tier':<8} {'Description':<34} {'Count':>8} {'Passed':>8} {'Failed':>8} {'Pass Rate':>10}")
    print(sep_single)

    for tier in sorted(collector.stats.keys()):
        s = collector.stats[tier]
        name = TIER_NAMES.get(tier, f"Tier {tier}")
        rate_str = f"{(s['passed'] / s['total'] * 100.0):.1f}%" if s["total"] > 0 else "N/A"
        print(f" Tier {tier:<3} {name:<34} {s['total']:>8} {s['passed']:>8} {s['failed']:>8} {rate_str:>10}")

    print(sep_single)
    total_rate_str = f"{overall_rate:.1f}%" if total_count > 0 else "N/A"
    print(f" {'TOTAL':<43} {total_count:>8} {total_passed:>8} {total_failed:>8} {total_rate_str:>10}")
    print(sep_double)
    print(f" Total Execution Duration: {duration_sec:.2f}s")

    if total_failed == 0 and total_count > 0:
        verdict = f"PASSED ({overall_rate:.1f}% Success Rate)"
        print(f" Overall Result:           \033[92m{verdict}\033[0m" if sys.stdout.isatty() else f" Overall Result:           {verdict}")
    else:
        verdict = f"FAILED ({total_failed} failures, {overall_rate:.1f}% Success Rate)"
        print(f" Overall Result:           \033[91m{verdict}\033[0m" if sys.stdout.isatty() else f" Overall Result:           {verdict}")

    print(sep_double + "\n")
    return total_failed


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Master E2E Test Runner CLI for YOLO NCNN Detector",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    group = parser.add_mutually_exclusive_group()
    group.add_argument(
        "--all",
        action="store_true",
        help="Run all 4 tiers (460 tests total)",
    )
    group.add_argument(
        "--tier",
        type=int,
        choices=[1, 2, 3, 4],
        help="Run a specific tier (Tier 1: 200, Tier 2: 200, Tier 3: 40, Tier 4: 20)",
    )
    parser.add_argument(
        "-v", "--verbose",
        action="store_true",
        help="Verbose output per test",
    )
    parser.add_argument(
        "--junit-xml",
        type=str,
        default=None,
        metavar="PATH",
        help="Output JUnit XML test results to specified path",
    )

    args = parser.parse_args()

    # Determine target tiers
    if args.tier is not None:
        target_tiers = [args.tier]
    else:
        # Default or --all: run all 4 tiers
        target_tiers = [1, 2, 3, 4]

    # Collect test directories to run
    test_paths: List[str] = [str(TIER_DIRS[t]) for t in target_tiers if TIER_DIRS[t].exists()]

    if not test_paths:
        print(f"ERROR: No test directories found for tiers {target_tiers}", file=sys.stderr)
        return 1

    # Prepare pytest arguments
    pytest_args: List[str] = list(test_paths)

    if args.verbose:
        pytest_args.append("-v")
    else:
        pytest_args.append("-q")

    if args.junit_xml:
        xml_path = Path(args.junit_xml).resolve()
        xml_path.parent.mkdir(parents=True, exist_ok=True)
        pytest_args.append(f"--junit-xml={xml_path}")

    # Set working directory to REPO_ROOT for consistent resolution
    os.chdir(str(REPO_ROOT))

    # Initialize collector and run pytest
    collector = TierResultCollector(target_tiers=target_tiers)
    start_time = time.perf_counter()

    pytest_exit_code = pytest.main(pytest_args, plugins=[collector])

    duration_sec = time.perf_counter() - start_time

    # Print summary report table
    failed_count = print_summary_table(collector, duration_sec)

    if failed_count > 0 or pytest_exit_code not in (pytest.ExitCode.OK, 0):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
