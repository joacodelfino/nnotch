#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nnotch-calendar-tests.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -parse-as-library -module-cache-path "${TMPDIR:-/tmp}/nnotch-module-cache" \
    Sources/NNotch/Managers/CalendarModels.swift \
    Sources/NNotch/Managers/CalendarLogic.swift \
    scripts/CalendarLogicTests.swift -o "$TEST_DIR/calendar-tests"
"$TEST_DIR/calendar-tests"
