#!/bin/bash
set -euo pipefail

xcodebuild -version
device_id="$(xcrun simctl list devices available --json | /usr/bin/python3 -c '
import json, sys
devices = json.load(sys.stdin)["devices"]
print(next(device["udid"] for runtime, entries in devices.items()
           if "iOS" in runtime for device in entries
           if device["name"].startswith("iPhone") and device["isAvailable"]))
')"
xcrun simctl bootstatus "$device_id" -b
xcodebuild -project DuoBrowser.xcodeproj -scheme DuoBrowser \
  -destination "platform=iOS Simulator,id=$device_id" \
  -parallel-testing-enabled NO \
  -test-timeouts-enabled YES \
  -default-test-execution-time-allowance 120 \
  -maximum-test-execution-time-allowance 180 \
  -resultBundlePath TestResults.xcresult \
  CODE_SIGNING_ALLOWED=NO test
