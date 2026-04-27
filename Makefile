SHELL := /bin/bash
.PHONY: bootstrap hooks doctor fast check full-check release-check release-verify build release test test-fast test-core test-infra test-coverage test-one ci-check lint format markdownlint python-tools-check shellcheck actionlint quality report-large-files secrets package package-dmg preview preview-version preview-dmg preview-dmg-version gh-harden run clean

bootstrap:
	scripts/bootstrap.sh

hooks:
	scripts/install-git-hooks.sh

doctor:
	scripts/doctor.sh

fast:
	scripts/check.sh fast

check:
	scripts/check.sh dev

# Local gate before tagging: dev check (includes fast-check) then a dev preview zip.
release-check: check preview

# Debug + release compile, fast tests, python (stricter than PR CI). `ci-check` is an alias.
full-check:
	scripts/check.sh full

ci-check: full-check

# Same gate as developer-preview tags: clean, release build, coverage tests.
release-verify:
	scripts/check.sh release

build:
	swift build

release:
	swift build -c release

# Default local test command: fast, readable, no coverage.
test: test-fast

test-fast:
	scripts/run-swift-test-fast.sh

test-core:
	swift test --filter NoteStreamCoreTests --disable-swift-testing

test-infra:
	swift test --filter NoteStreamInfrastructureTests --disable-swift-testing

# Slower. Use in CI/main/release checks, not constant local iteration.
test-coverage:
	scripts/run-swift-test-coverage.sh

# Usage:
# make test-one FILTER=ExternalJSONNotesSummarizerTests/testParsesValidJSONFromStdout
test-one:
	@test -n "$(FILTER)" || (echo "Usage: make test-one FILTER=SomeTestClass/testName" && exit 1)
	swift test --filter "$(FILTER)" --disable-swift-testing

lint:
	swift-format lint --strict --recursive Sources Tests
	swiftlint lint --strict

shellcheck:
	@shopt -s nullglob; shellcheck \
	  scripts/*.sh scripts/*/*.sh .githooks/*

actionlint:
	actionlint

quality: lint markdownlint shellcheck actionlint python-tools-check secrets report-large-files

# Non-failing: list Swift files over 300 lines (override: make report-large-files N=500).
N?=300
report-large-files:
	scripts/report-large-files.sh $(N)

secrets:
	scripts/check-secrets.sh

format:
	swift-format format --in-place --recursive Sources Tests

markdownlint:
	markdownlint README.md docs/**/*.md

python-tools-check:
	python3 -m py_compile docs/tools/notestream-diarize-pyannote.py

# Default VERSION=dev for local developer preview artifacts.
VERSION?=dev
package:
	scripts/packaging/build-preview-app-zip.sh $(VERSION)

package-dmg:
	scripts/packaging/build-preview-dmg.sh $(VERSION)

preview: package

preview-version:
	@test -n "$(VERSION)" || (echo "Usage: make preview-version VERSION=0.1.0-beta.1" && exit 1)
	$(MAKE) package VERSION=$(VERSION)

preview-dmg: package-dmg

preview-dmg-version:
	@test -n "$(VERSION)" || (echo "Usage: make preview-dmg-version VERSION=0.1.0-beta.1" && exit 1)
	$(MAKE) package-dmg VERSION=$(VERSION)

gh-harden:
	scripts/admin/gh-repo-harden.sh

# Starts the app and keeps running until you quit NoteStream.
# Use this only for manual local development.
run:
	swift run NoteStreamApp

clean:
	rm -rf .build
