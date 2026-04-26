.PHONY: bootstrap hooks doctor fast check build release test lint format markdownlint python-tools-check shellcheck actionlint quality preview preview-version preview-dmg preview-dmg-version gh-harden run clean

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
	swift test --enable-code-coverage --disable-swift-testing

lint:
	swift-format lint --strict --recursive Sources Tests
	swiftlint lint --strict

shellcheck:
	shellcheck scripts/*.sh .githooks/*

actionlint:
	actionlint

quality: lint markdownlint shellcheck actionlint python-tools-check

format:
	swift-format format --in-place --recursive Sources Tests

markdownlint:
	markdownlint README.md docs/**/*.md

python-tools-check:
	python3 -m py_compile docs/tools/notestream-diarize-pyannote.py

preview:
	scripts/build-preview-app-zip.sh dev

preview-version:
	@test -n "$(VERSION)" || (echo "Usage: make preview-version VERSION=0.1.0-beta.1" && exit 1)
	scripts/build-preview-app-zip.sh $(VERSION)

preview-dmg:
	scripts/build-preview-dmg.sh dev

preview-dmg-version:
	@test -n "$(VERSION)" || (echo "Usage: make preview-dmg-version VERSION=0.1.0-beta.1" && exit 1)
	scripts/build-preview-dmg.sh $(VERSION)

gh-harden:
	scripts/gh-repo-harden.sh

# Starts the app and keeps running until you quit NoteStream.
# Use this only for manual local development.
run:
	swift run NoteStreamApp

clean:
	rm -rf .build

