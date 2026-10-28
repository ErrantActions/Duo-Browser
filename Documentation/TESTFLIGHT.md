# Duo Browser: protected TestFlight publishing

The installed app is **Duo Browser**. Its existing App Store Connect listing is
**DuoKit**. This document describes owner-only beta distribution, not public
App Store submission.

## Fresh repository and existing Apple resources

This public repository has a new Git database and one initial commit containing
only the reviewed source snapshot. It is not a fork and does not import an
earlier repository's branches, tags, commits, checkpoint refs, logs, or artifacts.

| Item | Value |
| --- | --- |
| Repository | `ErrantActions/Duo-Browser` |
| Project / scheme | `DuoBrowser.xcodeproj` / `DuoBrowser` |
| Bundle identifier | `com.errantactions.duobrowser` |
| Apple team | `QM3794NUZS` |
| Existing App Store Connect app | [6827739657](https://appstoreconnect.apple.com/apps/6827739657/distribution) |
| Primary language / SKU | English (U.S.) / `duobrowser-ios` |
| Distribution profile | `Duo Browser App Store` |
| Intended testers | Owner only, internal testing with manual build assignment |

These identifiers are configuration metadata, not passwords or private keys.
Do not recreate the app record, revoke certificates, or generate replacement
API keys merely because the source repository changed. Existing valid signing
resources can be reused after checking their app, team, expiry, and key pairing.

## Current release state

- Unsigned simulator CI runs on the standard public `macos-15` runner. It receives
  no signing secrets and does not upload to Apple.
- The TestFlight workflow is disabled. Its verification job also requires the
  repository variable `ENABLE_TESTFLIGHT` to be exactly `true`.
- The new `app-store` environment requires owner approval, disables administrator
  bypass, and permits only `main`.
- Signing secrets are not imported through Git. GitHub does not expose their
  decrypted values for copying from another repository.
- Native tests, signed archive/export, Apple processing, build assignment, and
  physical-phone installation must each be verified for the relevant build.

## Configure signing privately

Keep all signing files outside the checkout in a protected local directory.
The [local setup helper](../Tools/Set-TestFlightSecrets.ps1) reads them directly
and sends secret values to GitHub over stdin without printing them.

Variables in the `app-store` environment:

- `APP_BUNDLE_ID`: `com.errantactions.duobrowser`
- `APPLE_TEAM_ID`: `QM3794NUZS`

Required environment secrets:

- `DISTRIBUTION_CERTIFICATE_BASE64`: encrypted P12 containing its matching private key.
- `DISTRIBUTION_CERTIFICATE_PASSWORD`: P12 password.
- `PROVISIONING_PROFILE_BASE64`: the matching App Store Connect distribution profile.
- `APP_STORE_CONNECT_KEY_ID`: existing team API key identifier.
- `APP_STORE_CONNECT_ISSUER_ID`: team API issuer identifier.
- `APP_STORE_CONNECT_PRIVATE_KEY`: the original `.p8` text.

Example local paths, not files that belong in this repository:

```powershell
& .\Tools\Set-TestFlightSecrets.ps1 `
  -CertificatePath "$env:LOCALAPPDATA\DuoBrowser\Signing\distribution.p12" `
  -ProfilePath "$env:LOCALAPPDATA\DuoBrowser\Signing\Duo_Browser_App_Store.mobileprovision" `
  -ApiKeyPath "$env:LOCALAPPDATA\DuoBrowser\Signing\AuthKey_KEYID.p8"
```

Supply the actual approved file locations. Enter the issuer identifier and
existing P12 password only in the owner-visible terminal; the password prompt
is hidden. Never paste passwords or private keys into chat.

The VS Code task **Duo: Configure TestFlight signing secrets** also runs this
helper. Review and approve its process-only `RemoteSigned` policy before use.
It does not change persistent execution policy or trigger an Apple upload.

The helper verifies the main-only environment, profile CMS signature, app/team,
expiry, and P12 password. It does not create resources, move files, replace
environment protections, or enable TestFlight.

## Explicitly resume owner-only publishing

Only after signing setup, passing native tests, and explicit owner approval:

```powershell
gh variable set ENABLE_TESTFLIGHT --body true --repo ErrantActions/Duo-Browser
gh workflow enable testflight.yml --repo ErrantActions/Duo-Browser
gh workflow run testflight.yml --repo ErrantActions/Duo-Browser `
  --ref main -f confirm_upload=true
```

Approve the pending `app-store` deployment in GitHub only after reviewing the
exact commit and verification results. Its secrets are not released beforehand.
To pause again, disable the workflow and set `ENABLE_TESTFLIGHT` to `false`.

The release route uses the configured Xcode 27 runner. Confirm runner access
and billing separately; public repository visibility does not make larger
runners free.

## Signing and upload lifecycle

The [release script](../.github/scripts/testflight.sh) checks the expected app/
team/build number, validates profile distribution type and expiry, imports the
certificate into a temporary keychain, and archives for a physical iOS device.
It exports an App Store Connect IPA and uses Xcode's `altool` uploader, not a
separate Mac App Store Transporter installation.

Private signing values are removed from child-process environments before
archive tools run. The `.p8` is restored only as a protected temporary upload
file. Temporary keychain/profile/certificate/API-key files are removed on exit,
including failure. Signing files and IPA exports are never public artifacts.

The marketing version comes from `MARKETING_VERSION`; the upload's build number
comes from the TestFlight workflow run number. Before a first upload from this
new workflow, check the existing App Store Connect builds and ensure its number
is greater than any already accepted build. Do not rerun an already-successful
upload with the same version/build number.

## Verify distribution separately

1. Verify native tests, archive, export, and upload separately.
2. Wait for the build in [TestFlight](https://appstoreconnect.apple.com/apps/6827739657/testflight).
3. Let the owner resolve export-compliance or legal questions; do not invent an
   encryption exemption.
4. Use **Owner Testing**, with manual distribution and only the owner included.
   Do not create a public link or invite external testers without approval.
5. Assign the processed build and verify actual installation and launch through
   Apple's TestFlight app.

Successful delivery is not proof of completed Apple processing or phone launch.
Do not repeatedly upload solely because Apple has not displayed the build yet.
