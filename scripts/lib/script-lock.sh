#!/usr/bin/env bash

NOTESTREAM_REPO_LOCK_DIR="${NOTESTREAM_REPO_LOCK_DIR:-}"

cleanup_repo_lock() {
  if [[ "${NOTESTREAM_REPO_LOCK_HELD:-0}" == "1" ]] &&
    [[ -n "${NOTESTREAM_REPO_LOCK_DIR:-}" ]] &&
    [[ -d "$NOTESTREAM_REPO_LOCK_DIR" ]]; then
    rm -rf "$NOTESTREAM_REPO_LOCK_DIR"
  fi
}

acquire_repo_lock() {
  if [[ "${NOTESTREAM_REPO_LOCK_HELD:-0}" == "1" ]]; then
    return 0
  fi

  local repo_root="${REPO_ROOT:-$(pwd)}"
  local wait_seconds="${NOTESTREAM_SCRIPT_LOCK_WAIT_SEC:-30}"
  local lock_base="${NOTESTREAM_LOCK_BASE:-$repo_root/.lock}"
  local start

  start="$(date +%s)"

  mkdir -p "$lock_base"

  NOTESTREAM_REPO_LOCK_DIR="$lock_base/notestream-script.lock"
  export NOTESTREAM_REPO_LOCK_DIR

  while ! mkdir "$NOTESTREAM_REPO_LOCK_DIR" 2>/dev/null; do
    if [[ -f "$NOTESTREAM_REPO_LOCK_DIR/pid" ]]; then
      local owner_pid
      owner_pid="$(cat "$NOTESTREAM_REPO_LOCK_DIR/pid" 2>/dev/null || true)"

      if [[ -n "$owner_pid" ]] && ! kill -0 "$owner_pid" 2>/dev/null; then
        echo "Removing stale NoteStream script lock from dead PID $owner_pid"
        rm -rf "$NOTESTREAM_REPO_LOCK_DIR"
        continue
      fi

      echo "Another NoteStream script is running. PID: ${owner_pid:-unknown}"
      if [[ -n "${owner_pid:-}" ]]; then
        ps -p "$owner_pid" -o pid=,ppid=,etime=,stat=,command= 2>/dev/null || true
      fi
    else
      echo "Another NoteStream script is running."
    fi

    local now
    now="$(date +%s)"

    if (( now - start >= wait_seconds )); then
      echo "Timed out waiting for NoteStream script lock after ${wait_seconds}s." >&2
      echo "Run: scripts/diagnose-swiftpm-lock.sh" >&2
      exit 124
    fi

    sleep 2
  done

  echo "$$" > "$NOTESTREAM_REPO_LOCK_DIR/pid"
  date > "$NOTESTREAM_REPO_LOCK_DIR/started-at"

  export NOTESTREAM_REPO_LOCK_HELD=1
  trap cleanup_repo_lock EXIT INT TERM
}

