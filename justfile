# Portu — SwiftUI macOS Crypto Portfolio Dashboard

default:
    @just --list

# Generate Xcode project from project.yml
generate:
    xcodegen generate
    @echo "Project generated. Open Portu.xcodeproj"

# Build the app (Debug)
build:
    xcodebuild -scheme Portu -configuration Debug -skipMacroValidation build

# Build the app (Release)
release:
    xcodebuild -scheme Portu -configuration Release -skipMacroValidation build

# Run all tests (SPM packages)
test-packages:
    cd Packages/PortuCore && swift test
    cd Packages/PortuNetwork && swift test
    cd Packages/PortuUI && swift test

# Run all tests (Xcode scheme)
test:
    xcodebuild -scheme Portu -configuration Debug -skipMacroValidation test

# Lint all Swift files
lint:
    swiftlint lint --quiet

# Auto-fix lintable violations
lint-fix:
    swiftlint --fix --quiet

# Format all Swift files
format:
    swiftformat .

# Build and launch with debug server on localhost:9999
debug-run: build
    #!/bin/bash
    APP=$(xcodebuild -scheme Portu -configuration Debug -showBuildSettings 2>/dev/null | grep ' BUILT_PRODUCTS_DIR' | head -1 | cut -d '=' -f 2- | sed 's/^[[:space:]]*//')/Portu.app
    if [ ! -d "$APP" ]; then echo "Could not locate Portu.app at $APP" >&2; exit 1; fi
    pkill -f "Portu.app/Contents/MacOS/Portu.*--debug-server" 2>/dev/null; sleep 0.5
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

# Stop the running debug app
debug-stop:
    pkill -f "Portu.app/Contents/MacOS/Portu.*--debug-server" || true
    @echo "Debug app stopped"

# Clean build artifacts
clean:
    xcodebuild -scheme Portu -skipMacroValidation clean
    rm -rf DerivedData .build
