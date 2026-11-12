SHELL := /bin/bash

SOURCES := src/main.sh $(wildcard src/lib/*.sh)
SCRIPTS := scripts/build.sh tests/e2e/run.sh tests/fixtures/fake-xray tests/fixtures/fake-sing-box

.PHONY: all build build-check lint fmt test check

all: build

# Bundle src/ into the single-file release.
build:
	@scripts/build.sh

build-check:
	@scripts/build.sh --check

# The bundle is linted as a whole program; the modules are linted on their
# own without the checks that need to see across files.
lint: build-check
	shellcheck toastbox.sh $(SCRIPTS)
	shellcheck -e SC2034,SC2154 $(SOURCES) tests/unit/mocks.bash
	shfmt -i 2 -ci -d src scripts tests/e2e tests/unit/mocks.bash tests/fixtures

fmt:
	shfmt -i 2 -ci -w src scripts tests/e2e tests/unit/mocks.bash tests/fixtures

test:
	bats tests/unit

check: lint test
