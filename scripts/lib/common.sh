#!/usr/bin/env bash
# Shared helpers for repo scripts (source with: . "$(dirname "$0")/lib/common.sh" from scripts/)

section() {
  echo ""
  echo "=============================="
  echo "$1"
  echo "=============================="
}
