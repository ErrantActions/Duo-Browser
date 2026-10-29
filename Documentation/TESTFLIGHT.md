# Duo Browser: secure manual builds and TestFlight

The app remains **Duo Browser**, with the existing **DuoKit** App Store Connect
listing. This project uses its checked-in `DuoBrowser.xcodeproj` and
`DuoBrowser` scheme, not another app's generator, SDK integration, or identity.
The source snapshot began with a fresh root commit; normal reviewed development
commits may follow. The original repository remains privately preserved.

## App identity

| Item | Duo configuration |
| --- | --- |
| Public repository | `ErrantActions/Duo-Browser` |
| Bundle identifier | `com.errantactions.duobrowser` |
| Apple team | `QM3794NUZS` |
| App Store Connect app | [6827739657](https://appstoreconnect.apple.com/apps/6827739657/distribution) |
| Marketing version | `1.0`, from `MARKETING_VERSION` |
| Deployment target | iOS 17 |
| Distribution profile | `Duo Browser App Store`, matching this bundle/team |
| Intended testers | Owner-only internal testing, manual build assignment |

Team/bundle/app IDs are configuration metadata, not passwords. Do not copy
another app's IDs or recreate valid Apple resources because a repository changed.
This app currently declares no custom signing entitlements; camera/microphone/
location purpose strings and the used-API privacy manifest are checked in.
Do not add push, app-group, iCloud, or other capabilities without a feature need.
Export-compliance answers remain an owner decision; no exemption is fabricated.

## Standard runner and cost

Both workflows use **`xcode-27`**, explicitly listed under GitHub's
[standard runners for public repositories](https://docs.github.com/en/actions/reference/runners/github-hosted-runners#standard-github-hosted-runners-for-public-repositories).
[GitHub billing documentation](https://docs.github.com/en/billing/concepts/product-billing/github-actions)
states that standard public-repository compute is free; larger runners can
still be billed. This setup changes no billing settings and selects no larger
runner.

The [published runner image](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)
provides Xcode **27.1 release** and iOS **27.1**. `DEVELOPER_DIR` pins that
installation rather than the separate release candidate. Simulator selection
requires the matching runtime and prefers iPhone Duo when available.
If the image removes that installation, fail clearly and review the pin;
do not silently switch SDKs. Preview runner images have GitHub's stated SLA limits.

## Manual unsigned validation

No push or pull request automatically runs these workflows.

```powershell
gh workflow run ios.yml --repo ErrantActions/Duo-Browser --ref main `
  -f confirm_run=true -f save_summary=false
```

This runs build/security contracts, Python plist tests, and native unit/UI tests
with `CODE_SIGNING_ALLOWED=NO`. It never receives Apple signing secrets.
The simulator job is bounded to 30 minutes and its native step to 20 minutes.

Optional `save_summary=true` publishes **only whitelisted numeric test counts**,
with one-day retention. It does not publish an app, IPA, screenshot, result
bundle, profile, keychain, API key, or raw diagnostic logs. A missing result
bundle is reported as unavailable, never as passing tests.

The full UI suite is intentionally separate from the faster TestFlight upload
path. Run it when checking UI changes or a release candidate, not automatically
as a duplicate deployment job. A successful upload does not imply the UI suite
passed.

## Private signing setup

The new repository's signing environment must be populated privately; encrypted
secret values cannot be read back and copied through GitHub's API. Reuse valid
existing resources only after verifying them.

The `app-store` environment disables administrator bypass and allows only the
`main` branch. At the owner's request, it has no separate deployment-review
click: manually starting the confirmed TestFlight workflow authorizes the run.
The local helper checks the remaining protections without changing them.

Nonsecret environment variables:

- `APP_BUNDLE_ID`: `com.errantactions.duobrowser`
- `APPLE_TEAM_ID`: `QM3794NUZS`
- `APP_STORE_CONNECT_APP_ID`: `6827739657`

Encrypted environment secrets:

- `DISTRIBUTION_CERTIFICATE_BASE64`
- `DISTRIBUTION_CERTIFICATE_PASSWORD`
- `PROVISIONING_PROFILE_BASE64`
- `APP_STORE_CONNECT_KEY_ID`
- `APP_STORE_CONNECT_ISSUER_ID`
- `APP_STORE_CONNECT_PRIVATE_KEY`

The `.p8` must be an **App Store Connect team upload key**, with a matching
issuer and sufficient app/build access, not an APNs provider key. A `.p8`
extension alone does not establish purpose. Apple metadata lookup verifies
authentication and this app's bundle before compilation.
That read-only lookup is not proof of every upload permission; the owner must
verify the key's upload-capable role in App Store Connect as well.

Use the [local setup helper](../Tools/Set-TestFlightSecrets.ps1) from an
owner-visible terminal. These are example protected paths; use the actual
approved locations outside the checkout:

```powershell
& .\Tools\Set-TestFlightSecrets.ps1 `
  -CertificatePath "$env:LOCALAPPDATA\DuoBrowser\Signing\distribution.p12" `
  -ProfilePath "$env:LOCALAPPDATA\DuoBrowser\Signing\Duo_Browser_App_Store.mobileprovision" `
  -ApiKeyPath "$env:LOCALAPPDATA\DuoBrowser\Signing\AuthKey_KEYID.p8"
```

The VS Code task **Duo: Configure TestFlight signing secrets** also opens this
helper. Review its one-process `RemoteSigned` policy before use; it does not
change persistent execution policy. Enter the existing P12 password only in
the masked terminal prompt, never in chat.

The helper verifies profile CMS signature, app/team, expiry/distribution type,
certificate membership, matching private/public keys, and certificate expiry.
It sends secret values over stdin to GitHub without printing them or putting
passwords in process arguments. It does not generate keys, move files, replace
environment protections, enable a workflow, or upload an app.

Repository admins, anyone with write access, the owner account, and the exact
release code must remain trusted. A writer can start the confirmed release
without a second reviewer. Protect GitHub and Apple accounts with MFA, keep
write access restricted, and review release commits; encrypted secrets cannot
protect against running malicious workflow code.

## Release preflight and build numbers

The release is one owner-approved macOS job:

1. Run local build/security contract tests.
2. Before native compilation, open the encrypted P12 and confirm its private key
   matches its certificate. Validate the certificate's identity/expiry and
   membership in the matching App Store distribution profile.
3. Check profile team, bundle, expiry, UUID/type and every custom entitlement
   declared by this project's resolved Release build settings. Do not add a
   capability to make a mismatched profile pass.
4. Use a short-lived ES256 App Store Connect JWT to verify this app and enumerate
   its existing uploaded build versions. No token/private key is printed.
5. Select a numeric `CFBundleVersion` strictly greater than all enumerated builds.
   A new repository's workflow run counter is **not** used as the build number.
6. Remove all temporary preflight signing material, then run all native unit
   tests once. UI automation remains in the separate full validation workflow.
7. Revalidate signing and the selected number, archive for `generic/platform=iOS`,
   verify the archive's embedded bundle/build values, export an App Store Connect
   IPA, and upload with Xcode's `altool`.
   The build number is checked again immediately before delivery in case another
   uploader used it during compilation. Apple still enforces uniqueness against
   unavoidable concurrent-upload races.

Builds use one to three numeric components: major 1-9999, minor/patch 0-99.
For example, the next value after `1000` is `1000.0.1`; after `10.99.99` it is
`11`. An optional manual `build_number` must still exceed Apple's existing
uploads. Unreadable/partial build history, denied API access, invalid versions,
or a superseded number fail closed rather than guessing an offset.

Generated keychain passwords and personal certificate identities are masked.
Private signing values are scoped to signing steps, removed from child-process
environments before archive tools run, and restored only as restricted temporary
files when required. Cleanup removes certificate/profile/API-key files and the
temporary keychain and restores the original keychain search list, including
on failure. No signing material or raw private diagnostics become artifacts.

## Owner-approved TestFlight run

TestFlight remains disabled and `ENABLE_TESTFLIGHT=false` until signing setup,
reviewed source, and explicit owner approval are ready:

```powershell
gh variable set ENABLE_TESTFLIGHT --body true --repo ErrantActions/Duo-Browser
gh workflow enable testflight.yml --repo ErrantActions/Duo-Browser
gh workflow run testflight.yml --repo ErrantActions/Duo-Browser --ref main `
  -f confirm_upload=true -f save_summary=false
```

There is no second `Review deployments` step. Review the exact commit before
starting the workflow; its preflight gets secrets only in that confirmed
main-branch job. Forks and public PRs do not get them. To pause, disable the
workflow and set the activation variable to false.

## What is and is not verified

The TestFlight path keeps security/contracts, signing preflight, all native
unit tests, and archive/export validation. It does not gate owner-only betas on
UI automation; the full simulator workflow still runs both native suites.
Do not report a green unit-only upload as a passing full UI validation.

Windows checks prove local helper/contracts, not native iOS compilation.
Native validation requires Xcode. Existing run
[40766913589](https://github.com/ErrantActions/Duo-Browser/actions/runs/40766913589)
compiled the source and passed 61 unit tests plus the panel/tab-grid UI cases;
two HTTPS UI cases failed because they depended on a changed external page
heading. The corrected assertions and new workflow still need an approved
native run. No signed upload is claimed.

After an upload:

1. Confirm archive, export, and delivery success separately.
2. Wait for [Apple processing](https://appstoreconnect.apple.com/apps/6827739657/testflight).
3. Let the owner resolve compliance/legal prompts.
4. Assign the processed build to **Owner Testing**, with manual distribution and
   only the owner included. No public links or external testers without approval.
5. Install through Apple's TestFlight app and confirm actual launch, browsing,
   native panel permissions, and scanning on a supported physical phone.

Delivery is not proof of completed processing or phone installation. Do not
repeatedly upload solely because Apple has not displayed a build yet.
