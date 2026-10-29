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
The owner explicitly confirmed that this app uses only exempt Apple-provided
encryption. `Info.plist` now records `ITSAppUsesNonExemptEncryption=false` as
a Boolean, and the archive check requires that exact declaration.
Apple documents that including it avoids the repeated per-build questionnaire.
No France-distribution answer, store-territory change, or invented export
compliance code is added. Reassess the declaration before introducing custom
or non-exempt cryptography or another SDK.

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
It compiles with `build-for-testing` before booting the simulator, then runs the
selected tests with `test-without-building` using the same build directory.
Compilation errors therefore fail before the potentially slow simulator startup.

For an edge-control change, `test_scope=duo-panel` selects only the focused
native-strip geometry/navigation UI regression. It checks the collapsed
address on ordinary pages, absence of duplicate bottom chrome, a webpage
height above 85% of the window, no overlap with core edge buttons, address
connected URL-bubble toggling without a full sheet, keyboard focus,
invalid-input reporting, outside-tap cancellation, unique browser controls,
submission, and website navigation/refresh/clear. Screenshot pixels check live
light/dark page colors across the webpage, seam, and outer rail, plus the
bubble's material connection. UI runs disable the simulator's
hardware-keyboard connection so the on-screen keyboard is actually exercised.
It does not duplicate the unit suite that TestFlight will run and does not
claim full UI acceptance.

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

The owner enabled TestFlight after privately configuring the signing secrets.
Releases still require an explicit manual start with `confirm_upload=true`;
there are no push/PR uploads. To enable after a future pause:

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

### Verified first delivery: version 1.0, build 1

[Run 40795353458](https://github.com/ErrantActions/Duo-Browser/actions/runs/40795353458)
completed successfully for commit `3789f28b76aed59b33964ec7ed51bb60be06c7ad`.
The published logs verify:

- Security contracts and signing/App Store Connect preflight passed.
- All 61 native unit tests passed with no failures on Xcode 27.1.
- `ARCHIVE SUCCEEDED` and `EXPORT SUCCEEDED` for the physical-device archive.
- Apple reported `UPLOAD SUCCEEDED with no errors` at approximately 7:54 PM
  US Central on October 28, 2026.
- The temporary signing cleanup completed successfully.

Apple processing subsequently completed with **VALID** for build 1, ID
`79ca0ac0-fc8f-435d-bcab-e881c447a631`. Apple's initial beta detail reported
**MISSING_EXPORT_COMPLIANCE**. No encryption exemption or legal declaration was
submitted automatically. Subsequent Apple lookups reported
`usesNonExemptEncryption=false` for build 1; the agent did not submit that answer.

Owner Testing was separately confirmed as an internal group with one tester
and manual build assignment. Assignment, actual phone installation, and launch
are separate checkpoints and are not independently verified here. Do not
upload another copy to resolve a compliance or assignment question.

Windows checks prove local helper/contracts, not native iOS compilation.
Native validation requires Xcode. Earlier full UI runs found failures in the
demo/favorite flows; those tests remain in the full manual validation workflow.
This successful unit-only beta does not certify full UI behavior or physical
scanner/privacy flows.

The subsequent native Duo toolbar correction was independently verified in
[focused UI run 40802771417](https://github.com/ErrantActions/Duo-Browser/actions/runs/40802771417):
one test passed, zero failed. It measured a 466-point window, 382-point webpage,
and a 38-point native action beginning at x=399, then verified website
Previous/Next events, browser Refresh, and site clearing.

### Verified native-toolbar delivery: version 1.0, build 1.0.1

[Run 40803693515](https://github.com/ErrantActions/Duo-Browser/actions/runs/40803693515)
successfully delivered commit `98a53f730a9e49e1f8b7adbc38ea8c19daaf6138`.
All 62 native unit tests passed, followed by successful archive, export, and
Apple upload at approximately 9:15 PM US Central on October 28, 2026.
The focused toolbar UI regression was run separately on the same application
code; it was not duplicated in the upload job.

The immediate Apple API lookup had not yet listed build 1.0.1. A subsequent
lookup verified **VALID**, not expired, and `usesNonExemptEncryption=false`.
Assignment and actual installation remain separate unverified checkpoints.
Do not upload another copy just because processing is asynchronous. Build
**1.0.1** contains the native strip but still retains the duplicate bottom
chrome addressed by the edge-only update below.

### Verified edge-only layout and address editor

[Focused UI run 40807358107](https://github.com/ErrantActions/Duo-Browser/actions/runs/40807358107)
passed one test with zero failures for application commit
`62d20b187a3a226b2c26d43297f467424819d2d1`.
Native diagnostics measured a 466-by-678-point window and a webpage at
x=0, y=24, width=382, height=620. The native website action began at x=399
with width=38. The webpage used all height between the system's top and
bottom safe-area insets, without a duplicate bottom browser bar.

The regression also verified the collapsed address before any DuoKit
configuration, no overlap with core edge buttons, full-URL editing, Cancel
preserving Record 2, Go loading HTTPS, and website Previous/Next, Refresh,
and Clear. This proves that focused simulator flow, not physical-device
installation, the full UI suite, or delivery of this newer code.

### Verified edge-only delivery: version 1.0, build 1.0.2

[Run 40808360983](https://github.com/ErrantActions/Duo-Browser/actions/runs/40808360983)
delivered commit `e311a9516248fa6d421681f72bcc627f660c905c`, with the same
application code as the focused UI pass above. Signing preflight selected
build **1.0.2** above all existing App Store Connect uploads, then removed its
temporary signing material before tests. All **63 native unit tests** passed,
including the address-editor scene-reactivation/capability regression.

The logs separately confirm `ARCHIVE SUCCEEDED`, `EXPORT SUCCEEDED`, and
`UPLOAD SUCCEEDED with no errors` on October 29, 2026 at 03:02 UTC.
The focused UI test was not duplicated in this release job.
The initial Apple API lookup had not yet listed 1.0.2. A subsequent lookup
verified **VALID**, not expired, with `usesNonExemptEncryption=null`. Apple's
internal and external beta states are **MISSING_EXPORT_COMPLIANCE**.
The owner must answer the export-compliance prompt truthfully in
[App Store Connect](https://appstoreconnect.apple.com/apps/6827739657/testflight).
No compliance answer was invented or submitted automatically.

The upload key's beta-group read returned HTTP 403, so Owner Testing assignment
could not be independently verified. No broader key permissions, public links,
external testers, or automatic group-distribution policy were enabled.
After resolving compliance, the owner should confirm this build's assignment
to the existing owner-only internal group. Actual phone installation remains
unverified.

### Verified two-stage address editing and unique browser controls

[Focused UI run 40813672395](https://github.com/ErrantActions/Duo-Browser/actions/runs/40813672395)
passed one test with zero failures for commit
`64a94d811de9f505af85a7da8b3e8cef28a7a00a`.
The first address-icon tap exposed exactly one editable field and one on-screen
keyboard, with no full editor or duplicate bottom chrome. The field and native
icon shared the same vertical center (y=258); the resting webpage remained
382-by-620 points in a 466-by-678-point window.

The test counted one each of Address, Back, Refresh, Tabs, Menu, and Clear,
rejected an unsafe URL inline, promoted the typed draft with a second tap on
the same icon, and verified full-editor Cancel and outside-bubble dismissal
preserved Record 2. Compact keyboard Go loaded HTTPS. Website Previous/Next,
Refresh, and Clear still passed. Keyboard-hidden or disabled website actions
were unavailable while typing. The compact accessibility container preserves
individual editable controls rather than overriding their identifiers.
This is focused simulator proof, not a full-suite or phone-installation claim.

### Verified two-stage address delivery: version 1.0, build 1.0.3

[Run 40814804265](https://github.com/ErrantActions/Duo-Browser/actions/runs/40814804265)
delivered commit `8de3d874e9d9e1db9c5633d6a6a463911e85c8fa`, with the same
application code as the focused two-stage UI pass above. Preflight selected
**1.0.3** above existing Apple uploads and validated signing before compilation.
All **63 native unit tests** passed with zero failures. The release did not
repeat the focused UI test.

The logs separately confirm `ARCHIVE SUCCEEDED`, `EXPORT SUCCEEDED`, and
`UPLOAD SUCCEEDED with no errors` on October 29, 2026 at 04:08 UTC.
Apple subsequently reported **VALID**, not expired, and
`usesNonExemptEncryption=null`. Both beta states are
**MISSING_EXPORT_COMPLIANCE**. The owner must answer that prompt truthfully in
[App Store Connect](https://appstoreconnect.apple.com/apps/6827739657/testflight),
then confirm assignment of **1.0.3** to the existing owner-only internal group.
No compliance answer, broader key permission, external testing, public link,
or automatic group-distribution policy was added. Group assignment and actual
phone installation remain unverified.

### Verified connected URL and matching rail backgrounds

[Focused UI run 40820895631](https://github.com/ErrantActions/Duo-Browser/actions/runs/40820895631)
passed one test with zero failures for commit
`9fff39405d4bbea7db43910bb25f9fa15e49fbc0`.
Actual screenshot samples at x=2, x=384, and x=464 matched CSS exactly:
RGB (224,245,236) for Teal and (20,42,61) for Navy. These span the webpage,
the seam, and the outer rail behind controls. Web content still occupied
x=0, y=24, width=382, height=620 in a 466-by-678-point window and did not
overlap the buttons.

The connected material in the page-to-URL gap measured RGB (197,205,212)
over the Navy page, proving that the bubble decoration continued into the
rail. The single **URL** button retained its bounded caption, remained
hittable, and closed the bubble on a second tap without opening a larger
editor. Cancellation preserved Record 2; input validation, keyboard Go,
unique browser controls, website navigation, refresh, and clear also passed.
This is focused simulator proof, not full UI acceptance or phone installation.

### Verified connected URL and automatic compliance: version 1.0, build 1.0.4

[Run 40823535016](https://github.com/ErrantActions/Duo-Browser/actions/runs/40823535016)
delivered commit `df5552495dc14f21cd587b913cdfa94c2a947c6b`, with the same
application code as the focused pixel-based UI pass above. All **64 native unit
tests** passed, including a real visible WebKit document's initial and updated
CSS background colors, retained WebView identity, and start-page color reset.
The test restores its temporary key window. No tests were removed or skipped
to release the app.

Preflight selected **1.0.4** above existing uploads. The logs separately verify
`ARCHIVE SUCCEEDED`, `Archive exempt-encryption declaration verified`,
`EXPORT SUCCEEDED`, and `UPLOAD SUCCEEDED with no errors` on October 29, 2026
at 05:40 UTC. The archive check requires the actual app plist's
`ITSAppUsesNonExemptEncryption` Boolean to remain `false`.

Apple subsequently reported **VALID**, not expired,
`usesNonExemptEncryption=false`, internal **READY_FOR_BETA_TESTING**, and
external **READY_FOR_BETA_SUBMISSION**. It no longer reports
**MISSING_EXPORT_COMPLIANCE** for this build: the owner-confirmed plist answer
was accepted automatically. No France-distribution answer, store-territory
change, export-compliance code, public testing link, or external review
submission was added.

Owner Testing assignment and actual phone installation remain unverified.
The upload key's earlier restricted group visibility was not bypassed or
broadened. Earlier builds' compliance states are historical and are not changed
retroactively by this new plist.

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
