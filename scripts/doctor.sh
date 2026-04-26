#!/usr/bin/env bash
set -euo pipefail

status=0

check() {
  name="$1"
  command="$2"

  if eval "$command" >/dev/null 2>&1; then
    echo "OK: $name"
  else
    echo "MISSING: $name"
    status=1
  fi
}

check "Xcode" "xcodebuild -version"
check "Swift" "swift --version"
check "swift-format" "swift-format --version"
check "SwiftLint" "swiftlint version"
check "markdownlint" "markdownlint --version"
check "ShellCheck" "shellcheck --version"
check "actionlint" "actionlint -version"
check "git" "git --version"

if command -v ollama >/dev/null 2>&1; then
  echo "OK: Ollama installed"
else
  echo "OPTIONAL: Ollama not installed"
fi

if command -v ffmpeg >/dev/null 2>&1; then
  echo "OK: ffmpeg installed"
else
  echo "OPTIONAL: ffmpeg not installed. Needed for some diarization scripts."
fi

exit "$status"

