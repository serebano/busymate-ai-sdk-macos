#!/bin/bash
set -euo pipefail
xcodebuild -version
swift --version
python3 scripts/verify-release.py
swift package dump-package >/dev/null
xcodebuild -scheme BusymateAI -destination 'generic/platform=macOS' -derivedDataPath .build-derived -jobs 2 build
swift test --jobs 2
sdk=$(xcrun --sdk macosx --show-sdk-path)
arch=$(uname -m)
xcrun swiftc -typecheck -target "${arch}-apple-macos12.0" -sdk "$sdk" -I .build-derived/Build/Products/Debug Examples/ChatWindowController.swift
echo "typechecked Examples/ChatWindowController.swift against the built BusymateAI module"
