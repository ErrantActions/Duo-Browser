#!/bin/bash
set -euo pipefail

suite="${1:-all}"
if [[ "$#" -gt 1 || ( "$suite" != all && "$suite" != unit && "$suite" != duo-panel ) ]]; then
  echo "::error::Choose all, unit, or duo-panel for the native test suite."
  exit 1
fi
set --
if [[ "$suite" == unit ]]; then
  set -- -only-testing:DuoBrowserTests
elif [[ "$suite" == duo-panel ]]; then
  set -- -only-testing:DuoBrowserUITests/BrowserUITests/testDuoRightPaneKeepsWebsiteVisibleAndDeliversNavigation
fi

xcodebuild -version
expected="${EXPECTED_IOS_SDK:?An explicit iOS SDK must be selected}"
sdk="$(xcrun --sdk iphoneos --show-sdk-version)"
if [[ "$sdk" != "$expected" && "$sdk" != "$expected".* ]]; then
  echo "::error::The selected Xcode does not provide the pinned iOS SDK."
  exit 1
fi
device_id="$(xcrun simctl list devices available --json | node .github/scripts/simulator.cjs)"
mkdir -p build
xcodebuild -project DuoBrowser.xcodeproj -scheme DuoBrowser \
  -destination "platform=iOS Simulator,id=$device_id" \
  -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO build-for-testing
xcrun simctl bootstatus "$device_id" -b
xcodebuild -project DuoBrowser.xcodeproj -scheme DuoBrowser \
  -destination "platform=iOS Simulator,id=$device_id" \
  -derivedDataPath build/DerivedData \
  -parallel-testing-enabled NO \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 120 \
  -maximum-test-execution-time-allowance 180 \
  -resultBundlePath build/Tests.xcresult \
  "$@" \
  CODE_SIGNING_ALLOWED=NO test-without-building
