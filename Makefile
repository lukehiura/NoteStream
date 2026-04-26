.PHONY: bootstrap hooks doctor fast check build release test lint format markdownlint run clean

bootstrap:
	scripts/bootstrap.sh

hooks:
	scripts/install-git-hooks.sh

doctor:
	scripts/doctor.sh

fast:
	scripts/fast-check.sh

check:
	scripts/dev-check.sh

build:
	swift build

release:
	swift build -c release

test:
	swift test --enable-code-coverage

lint:
	swift-format lint --strict --recursive Sources Tests
	swiftlint lint --strict

format:
	swift-format format --in-place --recursive Sources Tests

markdownlint:
	markdownlint README.md docs/**/*.md

# Starts the app and keeps running until you quit NoteStream.
# Use this only for manual local development.
run:
	swift run NoteStreamApp

clean:
	rm -rf .build

