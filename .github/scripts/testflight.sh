#!/bin/bash
set -euo pipefail
umask 077

mode="${1:-upload}"
if [[ "$mode" != preflight && "$mode" != upload ]]; then
  echo "::error::Choose preflight or upload."
  exit 1
fi
for name in APP_BUNDLE_ID APPLE_TEAM_ID APP_STORE_CONNECT_APP_ID \
  DISTRIBUTION_CERTIFICATE_BASE64 DISTRIBUTION_CERTIFICATE_PASSWORD \
  PROVISIONING_PROFILE_BASE64 APP_STORE_CONNECT_KEY_ID \
  APP_STORE_CONNECT_ISSUER_ID APP_STORE_CONNECT_PRIVATE_KEY; do
  if [[ -z "${!name:-}" ]]; then
    echo "::error::Missing required signing configuration: $name"
    exit 1
  fi
done

duo_private_key="$APP_STORE_CONNECT_PRIVATE_KEY"
duo_certificate="$DISTRIBUTION_CERTIFICATE_BASE64"
duo_certificate_password="$DISTRIBUTION_CERTIFICATE_PASSWORD"
duo_profile="$PROVISIONING_PROFILE_BASE64"
unset APP_STORE_CONNECT_PRIVATE_KEY DISTRIBUTION_CERTIFICATE_BASE64 \
  DISTRIBUTION_CERTIFICATE_PASSWORD PROVISIONING_PROFILE_BASE64

if [[ "$APP_BUNDLE_ID" != com.errantactions.duobrowser ||
      "$APPLE_TEAM_ID" != QM3794NUZS ||
      ! "$APP_STORE_CONNECT_APP_ID" =~ ^[1-9][0-9]*$ ]]; then
  echo "::error::Signing metadata does not match the approved Duo Browser application."
  exit 1
fi
if [[ "$mode" == upload && ! "${BUILD_NUMBER:-}" =~ ^[1-9][0-9]{0,3}(\.(0|[1-9][0-9]?)){0,2}$ ]]; then
  echo "::error::Upload requires a preflight-validated build number."
  exit 1
fi
xcrun --find altool > /dev/null

mask_value() {
  local value="$1"
  value="${value//%/%25}"
  value="${value//$'\r'/%0D}"
  value="${value//$'\n'/%0A}"
  printf '::add-mask::%s\n' "$value"
}

work="$(mktemp -d "${RUNNER_TEMP:?Runner temporary directory is required}/duo-signing.XXXXXX")"
keychain="$work/signing.keychain-db"
keychain_password=""
profile_path=""
key_path=""
keychain_created=false
original_keychains=""

cleanup() {
  local status=$?
  trap - EXIT
  set +e
  local failed=false
  if [[ -n "$profile_path" ]]; then rm -f "$profile_path" || failed=true; fi
  if [[ -n "$key_path" ]]; then rm -f "$key_path" || failed=true; fi
  if [[ "$keychain_created" == true ]]; then
    security delete-keychain "$keychain" >/dev/null 2>&1 || failed=true
    local restored=()
    while IFS= read -r line; do
      line="${line#"${line%%[![:space:]]*}"}"
      line="${line%"${line##*[![:space:]]}"}"
      if [[ -n "$line" ]]; then restored+=("$line"); fi
    done <<< "$original_keychains"
    if [[ ${#restored[@]} -gt 0 ]]; then
      security list-keychains -d user -s "${restored[@]}" || failed=true
    fi
  fi
  rm -f "$work/certificate.p12" "$work/profile.mobileprovision" "$work/profile.plist" \
    "$work/profile.json" "$work/certificate.pem" "$work/cert-public.pem" \
    "$work/key-public.pem" "$work/private-tool.log" "$work/build-settings.json" \
    "$work/required-entitlements.json" "$work/export-options.json" \
    "$work/ExportOptions.plist" "$work/archive-info.json" || failed=true
  rmdir "$work" || failed=true
  if [[ "$failed" == true ]]; then
    echo "::error::Temporary signing material could not be completely cleaned up."
    status=1
  fi
  unset duo_private_key duo_certificate duo_certificate_password duo_profile keychain_password
  exit "$status"
}
trap cleanup EXIT
original_keychains="$(security list-keychains -d user | tr -d '"')"

printf '%s' "$duo_certificate" | base64 --decode > "$work/certificate.p12"
printf '%s' "$duo_profile" | base64 --decode > "$work/profile.mobileprovision"
unset duo_certificate duo_profile
if ! security cms -D -i "$work/profile.mobileprovision" > "$work/profile.plist" 2>"$work/private-tool.log"; then
  echo "::error::The distribution profile could not be decoded."
  exit 1
fi
if ! DUO_P12_PASSWORD="$duo_certificate_password" openssl pkcs12 \
  -in "$work/certificate.p12" -passin env:DUO_P12_PASSWORD -clcerts -nokeys \
  -out "$work/certificate.pem" >"$work/private-tool.log" 2>&1; then
  echo "::error::The encrypted P12 could not be opened. Check its password and certificate."
  exit 1
fi
if ! DUO_P12_PASSWORD="$duo_certificate_password" openssl pkcs12 \
  -in "$work/certificate.p12" -passin env:DUO_P12_PASSWORD -nocerts -nodes \
  2>"$work/private-tool.log" | openssl pkey -pubout -out "$work/key-public.pem" \
  2>>"$work/private-tool.log"; then
  echo "::error::The P12 does not provide a usable private signing key."
  exit 1
fi
openssl x509 -in "$work/certificate.pem" -pubkey -noout > "$work/cert-public.pem" 2>"$work/private-tool.log"
if ! cmp -s "$work/key-public.pem" "$work/cert-public.pem"; then
  echo "::error::The P12 certificate and private key do not match."
  exit 1
fi

python3 .github/scripts/plist-json.py "$work/profile.plist" "$work/profile.json"
xcodebuild -project DuoBrowser.xcodeproj -scheme DuoBrowser -configuration Release \
  -showBuildSettings -json CODE_SIGNING_ALLOWED=NO >"$work/build-settings.json" 2>"$work/private-tool.log"
entitlements="$(node .github/scripts/release-contract.cjs entitlements-path "$work/build-settings.json")"
if [[ -n "$entitlements" ]]; then
  python3 .github/scripts/plist-json.py "$entitlements" "$work/required-entitlements.json"
else
  printf '{}\n' > "$work/required-entitlements.json"
fi
node .github/scripts/release-contract.cjs validate-profile "$work/profile.json" \
  "$work/certificate.pem" "$work/required-entitlements.json" "$work/export-options.json"
plutil -convert xml1 -o "$work/ExportOptions.plist" "$work/export-options.json"

# Query Apple's accepted uploads; a new repository's workflow counter is not sufficient.
if [[ "$mode" == upload ]]; then BUILD_NUMBER_OVERRIDE="$BUILD_NUMBER"; fi
APP_STORE_CONNECT_PRIVATE_KEY="$duo_private_key" \
  BUILD_NUMBER_OVERRIDE="${BUILD_NUMBER_OVERRIDE:-}" \
  node .github/scripts/release-contract.cjs build-number
if [[ "$mode" == preflight ]]; then
  echo "Signing preflight passed. All temporary signing material is removed before tests."
  exit 0
fi

profile_uuid="$(/usr/libexec/PlistBuddy -c 'Print UUID' "$work/profile.plist")"
profile_name="$(/usr/libexec/PlistBuddy -c 'Print Name' "$work/profile.plist")"
profile_destination="$HOME/Library/MobileDevice/Provisioning Profiles/$profile_uuid.mobileprovision"
key_destination="$HOME/.appstoreconnect/private_keys/AuthKey_$APP_STORE_CONNECT_KEY_ID.p8"
if [[ -e "$profile_destination" || -e "$key_destination" ]]; then
  echo "::error::Refusing to overwrite an existing profile or API key. Use a clean runner."
  exit 1
fi
keychain_password="$(openssl rand -hex 32)"
mask_value "$keychain_password"
security create-keychain -p "$keychain_password" "$keychain"
keychain_created=true
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
if ! security import "$work/certificate.p12" -P "$duo_certificate_password" \
  -t cert -f pkcs12 -k "$keychain" -T /usr/bin/codesign -T /usr/bin/security \
  >"$work/private-tool.log" 2>&1; then
  echo "::error::Distribution identity import failed."
  exit 1
fi
unset duo_certificate_password
identity="$(security find-identity -v -p codesigning "$keychain" |
  sed -n 's/.*"\(Apple Distribution:.*\)".*/\1/p')"
if [[ -z "$identity" || "$identity" == *$'\n'* ]]; then
  echo "::error::Expected exactly one valid Apple Distribution signing identity."
  exit 1
fi
mask_value "$identity"
identity_name="${identity#Apple Distribution: }"
identity_name="${identity_name% ($APPLE_TEAM_ID)}"
mask_value "$identity_name"
security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
  -k "$keychain_password" "$keychain" >/dev/null 2>&1
security list-keychains -d user -s "$keychain"
mkdir -p "$(dirname "$profile_destination")"
profile_path="$profile_destination"
cp "$work/profile.mobileprovision" "$profile_path"

xcodebuild -project DuoBrowser.xcodeproj -scheme DuoBrowser \
  -configuration Release -destination 'generic/platform=iOS' \
  -archivePath build/DuoBrowser.xcarchive \
  PRODUCT_BUNDLE_IDENTIFIER="$APP_BUNDLE_ID" DEVELOPMENT_TEAM="$APPLE_TEAM_ID" \
  CURRENT_PROJECT_VERSION="$BUILD_NUMBER" CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="Apple Distribution" PROVISIONING_PROFILE_SPECIFIER="$profile_name" archive
python3 .github/scripts/plist-json.py \
  build/DuoBrowser.xcarchive/Products/Applications/DuoBrowser.app/Info.plist "$work/archive-info.json"
node .github/scripts/release-contract.cjs check-archive "$work/archive-info.json"
xcodebuild -exportArchive -archivePath build/DuoBrowser.xcarchive \
  -exportPath build/export -exportOptionsPlist "$work/ExportOptions.plist"

APP_STORE_CONNECT_PRIVATE_KEY="$duo_private_key" BUILD_NUMBER_OVERRIDE="$BUILD_NUMBER" \
  node .github/scripts/release-contract.cjs build-number
mkdir -p "$(dirname "$key_destination")"
key_path="$key_destination"
printf '%s' "$duo_private_key" > "$key_path"
unset duo_private_key
chmod 600 "$key_path"
ipa="$(find build/export -maxdepth 1 -name '*.ipa' -print -quit)"
if [[ -z "$ipa" ]]; then echo "::error::No IPA was exported."; exit 1; fi
xcrun altool --upload-app -f "$ipa" -t ios \
  --apiKey "$APP_STORE_CONNECT_KEY_ID" --apiIssuer "$APP_STORE_CONNECT_ISSUER_ID"
