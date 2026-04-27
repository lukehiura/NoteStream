#!/usr/bin/env bash
# Time-bounded `swift` CLI. Default: NOTESTREAM_SWIFTPM_TIMEOUT_SEC=300; for `swift test`, use
# NOTESTREAM_SWIFT_TEST_TIMEOUT_SEC (default 180). Never use --ignore-lock here.
#
# Policy: serialize repo scripts (see script-lock.sh); if SwiftPM reports a lock, inspect the PID;
# kill only a confirmed-stale Swift/Xcode tool process; prefer `swift package clean` over deleting
# internal .build files.

run_with_timeout() {
  local seconds="$1"
  shift
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "${seconds}s" "$@"
  elif command -v timeout >/dev/null 2>&1; then
    timeout "${seconds}s" "$@"
  else
    "$@"
  fi
}

swiftpm() {
  local seconds="${NOTESTREAM_SWIFTPM_TIMEOUT_SEC:-300}"
  if [[ "${1:-}" == "test" ]]; then
    seconds="${NOTESTREAM_SWIFT_TEST_TIMEOUT_SEC:-180}"
  fi
  run_with_timeout "$seconds" swift "$@"
}
