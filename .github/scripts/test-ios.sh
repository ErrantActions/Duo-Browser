#!/bin/bash
set -euo pipefail

suite="${1:-all}"
if [[ "$#" -gt 1 || ( "$suite" != all && "$suite" != unit && "$suite" != duo-panel && "$suite" != ask-duo ) ]]; then
  echo "::error::Choose all, unit, duo-panel, or ask-duo for the native test suite."
  exit 1
fi
set --
if [[ "$suite" == unit ]]; then
  set -- -only-testing:DuoBrowserTests
elif [[ "$suite" == duo-panel ]]; then
  set -- -only-testing:DuoBrowserUITests/BrowserUITests/testDuoNativeToolbarKeepsWebsiteVisibleAndDeliversNavigation
elif [[ "$suite" == ask-duo ]]; then
  set -- -only-testing:DuoBrowserUITests/BrowserUITests/testAskDuoBlocksPrivateTabs \
    -only-testing:DuoBrowserUITests/BrowserUITests/testAskDuoRequiresConsentAndConfirmsNavigation
fi
maximum_test_seconds=180
if [[ "$suite" == all || "$suite" == ask-duo ]]; then
  maximum_test_seconds=300
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
if [[ "$suite" != unit ]]; then
  defaults write com.apple.iphonesimulator ConnectHardwareKeyboard -bool NO
fi
xcrun simctl bootstatus "$device_id" -b
xcodebuild -project DuoBrowser.xcodeproj -scheme DuoBrowser \
  -destination "platform=iOS Simulator,id=$device_id" \
  -derivedDataPath build/DerivedData \
  -parallel-testing-enabled NO \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 120 \
  -maximum-test-execution-time-allowance "$maximum_test_seconds" \
  -resultBundlePath build/Tests.xcresult \
  "$@" \
  CODE_SIGNING_ALLOWED=NO test-without-building
