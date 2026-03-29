# Portu — SwiftUI macOS Crypto Portfolio Dashboard

default:
    @just --list

# Generate Xcode project from project.yml
generate:
    xcodegen generate
    @echo "Project generated. Open Portu.xcodeproj"

# Build the app (Debug)
build:
    xcodebuild -scheme Portu -configuration Debug build

# Build the app (Release)
release:
    xcodebuild -scheme Portu -configuration Release build

# Run all tests (SPM packages)
test-packages:
    cd Packages/PortuCore && swift test
    cd Packages/PortuNetwork && swift test
    cd Packages/PortuUI && swift test

# Run all tests (Xcode scheme)
test:
    xcodebuild -scheme Portu -configuration Debug test

# Lint all Swift files
lint:
    swiftlint lint --quiet

# Auto-fix lintable violations
lint-fix:
    swiftlint --fix --quiet

# Format all Swift files
format:
    swiftformat .

# Clean build artifacts
clean:
    xcodebuild -scheme Portu clean
    rm -rf DerivedData .build
