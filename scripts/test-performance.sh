#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nnotch-performance-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library -module-cache-path "${TMPDIR:-/tmp}/nnotch-module-cache" \
    Sources/NNotch/Managers/TimerCenter.swift \
    Sources/NNotch/Managers/ClipboardContent.swift \
    Sources/NNotch/Managers/CalendarModels.swift \
    Sources/NNotch/Managers/CalendarLogic.swift \
    Sources/NNotch/Support/ImageThumbnail.swift \
    scripts/PerformanceTests.swift -o "$TEST_DIR/performance-tests"
"$TEST_DIR/performance-tests"
