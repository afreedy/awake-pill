#!/bin/zsh
set -eu
cd "${0:A:h}"
mkdir -p AwakePill.app/Contents/MacOS
swiftc -target arm64-apple-macosx26.0 -parse-as-library -O AwakePill.swift -o AwakePill.app/Contents/MacOS/AwakePill
cp Info.plist AwakePill.app/Contents/Info.plist
codesign --force --sign - AwakePill.app
AwakePill.app/Contents/MacOS/AwakePill --check
