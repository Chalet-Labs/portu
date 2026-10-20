# Portu — SwiftUI macOS Crypto Portfolio Dashboard

# Same derived data as script/build_and_run.sh, and inside .build so the CI cache covers it
derived_data := ".build/DerivedData"

default:
    @just --list

# Generate Xcode project from project.yml
generate:
    xcodegen generate
    @echo "Project generated. Open Portu.xcodeproj"

# Build the app (Debug)
build:
    xcodebuild -scheme Portu -configuration Debug -derivedDataPath {{derived_data}} -skipMacroValidation build

# Build the app (Release)
release:
    xcodebuild -scheme Portu -configuration Release -skipMacroValidation build

# Run all tests (SPM packages)
test-packages:
    cd Packages/PortuCore && swift test
    cd Packages/PortuNetwork && swift test
    cd Packages/PortuUI && swift test

# Run all tests: the app and package suites, in one build (Xcode scheme)
test:
    xcodebuild -scheme Portu -configuration Debug -derivedDataPath {{derived_data}} -skipMacroValidation test

# Build the app, the packages and every test bundle once, for test-without-building
build-for-testing:
    xcodebuild -scheme Portu -configuration Debug -derivedDataPath {{derived_data}} -skipMacroValidation build-for-testing

# Run the tests that build-for-testing built, optionally filtered (e.g. -only-testing:PortuTests)
[positional-arguments]
test-without-building *args:
    xcodebuild -scheme Portu -configuration Debug -derivedDataPath {{derived_data}} -skipMacroValidation test-without-building "$@"

# Run app test suites: the ones named, or all of them except ReleaseAutomationTests
[positional-arguments]
test-app *suites:
    #!/usr/bin/env bash
    set -euo pipefail
    if [ $# -eq 0 ]; then
      filters=(-only-testing:PortuTests -skip-testing:PortuTests/ReleaseAutomationTests)
    else
      filters=()
      for suite in "$@"; do filters+=("-only-testing:PortuTests/$suite"); done
    fi
    xcodebuild -scheme Portu -configuration Debug -derivedDataPath {{derived_data}} -skipMacroValidation test "${filters[@]}"

# Run one package's tests, optionally filtered (pkg: Core, Network or UI)
[positional-arguments]
test-pkg pkg filter="":
    #!/usr/bin/env bash
    set -euo pipefail
    case "$1" in
      Core|Network|UI) ;;
      *) echo "test-pkg: pkg must be Core, Network or UI, got '$1'" >&2; exit 2 ;;
    esac
    cd "Packages/Portu$1"
    if [ -n "${2:-}" ]; then swift test --filter "$2"; else swift test; fi

# Run the package and app tests that changes since base can affect (rules: script/test-scope.json)
[positional-arguments]
test-affected base="origin/master":
    #!/usr/bin/env bash
    set -euo pipefail
    base="$1"
    groups="$(script/test_scope.sh --base "$base")"
    if [ "$groups" = none ]; then
      echo "no test groups affected by $base...HEAD"
      exit 0
    fi
    selected() { printf '%s\n' "$groups" | grep -qx "$1"; }
    echo "test groups affected by $base...HEAD:" $groups
    if selected core; then "{{just_executable()}}" test-pkg Core; fi
    if selected network; then "{{just_executable()}}" test-pkg Network; fi
    if selected ui; then "{{just_executable()}}" test-pkg UI; fi
    if selected release; then
      xcodebuild -scheme Portu -configuration Debug -derivedDataPath {{derived_data}} -skipMacroValidation test -only-testing:PortuTests
    elif selected app; then
      xcodebuild -scheme Portu -configuration Debug -derivedDataPath {{derived_data}} -skipMacroValidation test -only-testing:PortuTests -skip-testing:PortuTests/ReleaseAutomationTests
    fi

# Lint all Swift files
lint:
    swiftlint lint --quiet

# Lint with warnings as errors (what CI runs)
lint-strict:
    swiftlint lint --strict --quiet

# Auto-fix lintable violations
lint-fix:
    swiftlint --fix --quiet

# Format all Swift files
format:
    swiftformat .

# Fail if any Swift file needs formatting, without changing files (what CI runs)
format-check:
    swiftformat --lint .

# Build and launch with debug server on localhost:9999
debug-run: build
    #!/bin/bash
    APP=$(xcodebuild -scheme Portu -configuration Debug -derivedDataPath {{derived_data}} -showBuildSettings 2>/dev/null | grep ' BUILT_PRODUCTS_DIR' | head -1 | cut -d '=' -f 2- | sed 's/^[[:space:]]*//')/Portu.app
    if [ ! -d "$APP" ]; then echo "Could not locate Portu.app at $APP" >&2; exit 1; fi
    lsof -ti tcp:9999 | xargs kill 2>/dev/null || true; sleep 0.5
    open -n "$APP" --args --debug-server
    echo "Waiting for debug server..."
    attempts=0
    until curl -s http://localhost:9999/health > /dev/null 2>&1; do
      sleep 0.5
      attempts=$((attempts + 1))
      if [ $attempts -ge 60 ]; then echo "Timed out waiting for debug server after 30s" >&2; exit 1; fi
    done
    curl -s http://localhost:9999/health | jq .
    echo "Debug server ready at http://localhost:9999"

# Sign Debug builds from this checkout with your Apple Development identity, so keychain access survives rebuilds
[positional-arguments]
signing-setup *args:
    script/setup_local_signing.sh "$@"

# Stop the running debug app
debug-stop:
    lsof -ti tcp:9999 | xargs kill 2>/dev/null || true
    @echo "Debug app stopped"

# Clean build artifacts
clean:
    xcodebuild -scheme Portu -skipMacroValidation clean
    rm -rf DerivedData .build
