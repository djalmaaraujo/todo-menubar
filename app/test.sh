#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

mkdir -p build
swiftc -parse-as-library -o build/todobar-tests \
    TodoCore.swift \
    Tests.swift \
    -target arm64-apple-macos13.0

./build/todobar-tests
