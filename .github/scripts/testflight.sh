#!/bin/bash
set -euo pipefail
umask 077

for name in APP_BUNDLE_ID APPLE_TEAM_ID BUILD_NUMBER DISTRIBUTION_CERTIFICATE_BASE64 \
  DISTRIBUTION_CERTIFICATE_PASSWORD PROVISIONING_PROFILE_BASE64 \
  APP_STORE_CONNECT_KEY_ID APP_STORE_CONNECT_ISSUER_ID APP_STORE_CONNECT_PRIVATE_KEY; do
  if [[ -z "${!name:-}" ]]; then
    echo "::error::Missing required signing configuration: $name"
    exit 1
  fi
done
# Keep private material out of child-process environments during archive builds.
duo_private_key="$APP_STORE_CONNECT_PRIVATE_KEY"
duo_certificate="$DISTRIBUTION_CERTIFICATE_BASE64"
duo_certificate_password="$DISTRIBUTION_CERTIFICATE_PASSWORD"
duo_profile="$PROVISIONING_PROFILE_BASE64"
unset APP_STORE_CONNECT_PRIVATE_KEY DISTRIBUTION_CERTIFICATE_BASE64 \
  DISTRIBUTION_CERTIFICATE_PASSWORD PROVISIONING_PROFILE_BASE64
if [[ "$APP_BUNDLE_ID" != "com.errantactions.duobrowser" ||
      "$APPLE_TEAM_ID" != "QM3794NUZS" ||
      ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ||
      ! "$APP_STORE_CONNECT_KEY_ID" =~ ^[A-Z0-9]+$ ]]; then
  echo "::error::Signing identity or build number does not match the approved Duo Browser release."
  exit 1
fi
xcrun --find altool > /dev/null

work="$(mktemp -d "$RUNNER_TEMP/duo-signing.XXXXXX")"
keychain="$work/signing.keychain-db"
keychain_password="$(openssl rand -hex 32)"
profile_path=""
key_path=""
keychain_created=false
original_keychains="$(security list-keychains -d user | tr -d '"')"

cleanup() {
  local status=$?
  trap - EXIT
  set +e
  local cleanup_failed=false
  if [[ -n "$profile_path" ]]; then rm -f "$profile_path" || cleanup_failed=true; fi
  if [[ -n "$key_path" ]]; then rm -f "$key_path" || cleanup_failed=true; fi
  if [[ "$keychain_created" == true ]]; then
    security delete-keychain "$keychain" || cleanup_failed=true
  fi
  local restored=()
  while IFS= read -r line; do
    line="$(echo "$line" | xargs)"
    if [[ -n "$line" ]]; then restored+=("$line"); fi
  done <<< "$original_keychains"
  if [[ ${#restored[@]} -gt 0 ]]; then
    security list-keychains -d user -s "${restored[@]}" || cleanup_failed=true
  fi
  rm -f "$work/certificate.p12" "$work/profile.mobileprovision" \
    "$work/profile.plist" "$work/ExportOptions.plist" || cleanup_failed=true
  rmdir "$work" || cleanup_failed=true
  if [[ "$cleanup_failed" == true ]]; then
    echo "::error::Temporary signing material could not be completely removed."
    status=1
  fi
  unset duo_private_key duo_certificate duo_certificate_password duo_profile keychain_password
  exit "$status"
}
trap cleanup EXIT

printf '%s' "$duo_certificate" | base64 --decode > "$work/certificate.p12"
printf '%s' "$duo_profile" | base64 --decode > "$work/profile.mobileprovision"
unset duo_certificate duo_profile
security cms -D -i "$work/profile.mobileprovision" > "$work/profile.plist"
export SIGNING_WORK="$work"
/usr/bin/python3 - <<'PY'
import datetime
import os
import plistlib
import re
from pathlib import Path

work = Path(os.environ["SIGNING_WORK"])
profile = plistlib.loads((work / "profile.plist").read_bytes())
entitlements = profile["Entitlements"]
if profile["TeamIdentifier"] != [os.environ["APPLE_TEAM_ID"]]:
    raise SystemExit("The distribution profile belongs to a different Apple team.")
if entitlements["application-identifier"] != os.environ["APPLE_TEAM_ID"] + "." + os.environ["APP_BUNDLE_ID"]:
    raise SystemExit("The distribution profile belongs to a different application.")
if (profile.get("ProvisionedDevices") or profile.get("ProvisionsAllDevices")
        or entitlements.get("get-task-allow") or not profile.get("DeveloperCertificates")):
    raise SystemExit("An App Store Connect distribution profile is required.")
if profile["ExpirationDate"].replace(tzinfo=datetime.timezone.utc) <= datetime.datetime.now(datetime.timezone.utc):
    raise SystemExit("The distribution provisioning profile has expired.")
if not re.fullmatch(r"[A-Fa-f0-9-]{36}", profile["UUID"]):
    raise SystemExit("Invalid provisioning profile UUID.")
options = {
    "method": "app-store-connect", "destination": "export", "signingStyle": "manual",
    "teamID": os.environ["APPLE_TEAM_ID"], "signingCertificate": "Apple Distribution",
    "provisioningProfiles": {os.environ["APP_BUNDLE_ID"]: profile["Name"]},
    "manageAppVersionAndBuildNumber": False, "uploadSymbols": True,
}
(work / "ExportOptions.plist").write_bytes(plistlib.dumps(options))
PY
profile_uuid="$(/usr/libexec/PlistBuddy -c 'Print UUID' "$work/profile.plist")"
profile_name="$(/usr/libexec/PlistBuddy -c 'Print Name' "$work/profile.plist")"
profile_destination="$HOME/Library/MobileDevice/Provisioning Profiles/$profile_uuid.mobileprovision"
key_destination="$HOME/.appstoreconnect/private_keys/AuthKey_$APP_STORE_CONNECT_KEY_ID.p8"
if [[ -e "$profile_destination" || -e "$key_destination" ]]; then
  echo "::error::Signing would overwrite an existing profile or API key. Use a clean runner."
  exit 1
fi

security create-keychain -p "$keychain_password" "$keychain"
keychain_created=true
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$work/certificate.p12" -P "$duo_certificate_password" \
  -t cert -f pkcs12 -k "$keychain" -T /usr/bin/codesign -T /usr/bin/security
unset duo_certificate_password
security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
  -k "$keychain_password" "$keychain" > /dev/null
security list-keychains -d user -s "$keychain"
mkdir -p "$(dirname "$profile_destination")"
profile_path="$profile_destination"
cp "$work/profile.mobileprovision" "$profile_path"

xcodebuild -project DuoBrowser.xcodeproj -scheme DuoBrowser \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/DuoBrowser.xcarchive \
  PRODUCT_BUNDLE_IDENTIFIER="$APP_BUNDLE_ID" \
  DEVELOPMENT_TEAM="$APPLE_TEAM_ID" CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="Apple Distribution" \
  PROVISIONING_PROFILE_SPECIFIER="$profile_name" archive

/usr/bin/python3 - <<'PY'
import os
import plistlib
from pathlib import Path

info = plistlib.loads(Path("build/DuoBrowser.xcarchive/Products/Applications/DuoBrowser.app/Info.plist").read_bytes())
if info["CFBundleIdentifier"] != os.environ["APP_BUNDLE_ID"] or info["CFBundleVersion"] != os.environ["BUILD_NUMBER"]:
    raise SystemExit("The archived app identity or build number differs from the requested release.")
PY
xcodebuild -exportArchive -archivePath build/DuoBrowser.xcarchive \
  -exportPath build/export -exportOptionsPlist "$work/ExportOptions.plist"

mkdir -p "$(dirname "$key_destination")"
key_path="$key_destination"
printf '%s' "$duo_private_key" > "$key_path"
unset duo_private_key
chmod 600 "$key_path"
ipa="$(find build/export -maxdepth 1 -name '*.ipa' -print -quit)"
if [[ -z "$ipa" ]]; then echo "::error::Archive export produced no IPA."; exit 1; fi
xcrun altool --upload-app -f "$ipa" -t ios \
  --apiKey "$APP_STORE_CONNECT_KEY_ID" --apiIssuer "$APP_STORE_CONNECT_ISSUER_ID"
