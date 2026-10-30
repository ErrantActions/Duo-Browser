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
| Intended testers | Owner-only internal testing, automatic distribution through Owner Testing Auto |

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

For Ask Duo, `test_scope=ask-duo` selects four native UI cases: private exclusion,
page-free follow-up chat, compact/expanded quick-prompt review, and filtered
excerpt approval with confirmed navigation. These explicitly launch a visibly
labeled DEBUG-only scripted engine. They verify real UI/page-reader/controller
behavior, **not Apple model inference**. Release builds exclude that engine and
always use the real Apple provider; it is never an availability/error fallback.

The native unit suite separately tests conversation bounds, prompt metadata
omission, two-turn pipeline history, stale contexts, modal capability suspension
and clearing local data. Its real-provider probe first attempts a minimal plain
response, then the application's general/page schemas. Unavailable models, or
an untyped simulator `FoundationModels.LanguageModelError -1` on the minimal
probe, are explicitly skipped without a live-inference claim. Errors after a
usable minimal probe remain failures. Eligible physical hardware is required
to certify Apple Intelligence when that probe skips.

For scanning, `test_scope=scanner` selects compact input-sheet/no-target handling
and saved scanner preferences/reopening. `test_scope=page-tools` combines those
two with all four assistant cases without duplicating native unit execution.
Unit tests exercise actual WKWebView field insertion, beforeinput/input/change
and Enter events, normal form validation, cancellation, target changes, exact
barcode preservation, migration and on-disk settings. Camera recognition and
vibration still require a supported physical iPhone.
For local reading/start-page changes, `test_scope=reading` selects reader
appearance/persistence, original-page-state retention, real PDF share
presentation and private-export confirmation plus continued private-AI
exclusion, alongside the existing favorite-save/open start-page regression.
Native unit tests separately inspect actual PDF pages/searchable
text, metadata omission, extraction bounds, settings migration and capability
suspension. Audible speech output requires physical-device acceptance.
Private-tab coverage is a separate focused case. The complete integration case
has a bounded 300-second budget for navigation and slow simulator
accessibility; unit and Duo-only scopes retain their 180-second maximum.

### Verified scanner and conversational assistant UI

The scanner cases passed in
[run 40971329713](https://github.com/ErrantActions/Duo-Browser/actions/runs/40971329713):
explicit scanner Save/reopen persistence and compact no-target handling. The
surface measured **450 x 320.33 points** at y=349.67 in a 466 x 678-point window.

All four assistant cases passed in
[run 40976769613](https://github.com/ErrantActions/Duo-Browser/actions/runs/40976769613),
source `996f86078ae7ddaa8a8189c3c350f22556922ffe`: private exclusion, page-free
two-turn chat, compact/expanded shortcuts with explicit excerpt approval, and
real filtered-page reading plus confirmed HTTPS navigation. The compact chat
surface measured 309.67 points high; expansion and an unobscured shortcut above
the composer were checked. XCTest had previously reported a shortcut behind
the composer as hittable; the helper now uses the actually visible viewport.

Assistant replies in these UI cases are explicitly labeled DEBUG fixtures,
not Apple model inference. The Release app excludes that generator. The real
provider has a separate native probe; no device-generation or physical-camera
acceptance is implied by these six UI checks.

Optional `save_summary=true` publishes **only whitelisted numeric test counts**,
with one-day retention. It does not publish an app, IPA, screenshot, result
bundle, profile, keychain, API key, or raw diagnostic logs. A missing result
bundle is reported as unavailable, never as passing tests.

The full UI suite is intentionally separate from the faster TestFlight upload
path. Run it when checking UI changes or a release candidate, not automatically
as a duplicate deployment job. A successful upload does not imply the UI suite
passed.

## Automatic internal distribution

**Owner Testing Auto** is the active automatic-distribution group. It is an
internal group with `hasAccessToAllBuilds=true`, exactly the same single tester
as the original **Owner Testing** group, and no public link. No new person,
external group, or external review submission was added.

The original manual group remains unchanged. Apple's documented creation
request supports `hasAccessToAllBuilds`, but its update request does not, so
the automatic group was created separately rather than deleting the old one.
Group settings and membership were read back through the documented direct
group API. Build **1.0.4** was verified in the automatic group's build list,
with Apple reporting **IN_BETA_TESTING**.

Continue starting the existing confirmed GitHub TestFlight workflow manually.
After a future eligible upload completes processing and compliance, Apple
automatically distributes it to the internal automatic group; do not repeat
the old Add Builds step. This changes neither GitHub workflow triggers nor
signing permissions. Anyone subsequently added to this group would receive
future builds, so keep its membership owner-only.

This is the standard internal-group behavior described in Apple's
[internal tester instructions](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/).
Their Xcode Cloud exception does not apply to this GitHub-hosted Xcode workflow.
No new app build or upload was needed for the group configuration. Actual
phone download and launch still require device verification.

## Private signing setup

The new repository's signing environment must be populated privately; encrypted
secret values cannot be read back and copied through GitHub's API. Reuse valid
existing resources only after verifying them.

The `app-store` environment disables administrator bypass and allows only the
`main` branch. At the owner's request, it has no separate deployment-review
click: manually starting the confirmed TestFlight workflow authorizes the run.
The local helper checks the remaining protections without changing them.

The owner's delivery preference is to commit/push completed, validated app
changes and start the confirmed TestFlight workflow without another deployment
prompt. Keep the tests, signing preflight, main-only environment and owner-only
distribution gates. This is not authorization to upload broken intermediate
commits or to change the workflows into automatic push/pull-request triggers.

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
   Read-only Apple metadata requests use at most three bounded attempts for
   transient transport/timeouts or HTTP 5xx failures. Authorization failures,
   invalid app identities, signing failures and uploads are not blindly retried.
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

At the initial delivery check, group assignment and actual phone installation
were unverified. The automatic-distribution setup above subsequently verified
build 1.0.4 in **Owner Testing Auto** as **IN_BETA_TESTING**, with exactly the
same existing owner. The earlier HTTP 403 concerned a build-to-group endpoint;
the documented direct group resources worked without changing key permissions.
Actual phone installation remains unverified. Earlier builds' compliance states
are historical and are not changed retroactively by this new plist.

### Verified Ask Duo native acceptance

[Run 40835752864](https://github.com/ErrantActions/Duo-Browser/actions/runs/40835752864)
passed **two focused UI tests with zero failures** for commit
`c8a95b6c1acd476fb495b5d222e51728b076b38f`.
It compiled the real Apple Foundation Models / guided-generation implementation.
Native tests verified private-tab exclusion, no implicit page capture, explicit
Use This Excerpt approval, actual bundled-page filtering of input/form/editable
markers, a valid typed question, unavailable-model disabling, and native
navigation alert Cancel/Open followed by real HTTPS loading.

The simulator reported `onDeviceModelAvailable=false` and
`requested=false, modelUnavailable=true`. No live model answer was fabricated,
and this run is not proof of actual model generation. An eligible device with
Apple Intelligence enabled and its on-device model ready must complete that
acceptance check. The conditional test calls the real on-device model when
available; it has no fake model, network fallback, or alternate provider.

### Verified Ask Duo delivery: version 1.0, build 1.0.5

[Run 40837364527](https://github.com/ErrantActions/Duo-Browser/actions/runs/40837364527)
delivered commit `7e6d81a467f83b0f57875e7dcf3b9ec9ea862457`, with the same
application code as the focused Ask Duo UI pass above. All **72 native unit
tests** passed with zero failures, including eight new assistant context,
answer/link, lifecycle and clearing cases. The separate focused UI run was
not duplicated in the signed upload.

Preflight selected **1.0.5** above existing uploads. Logs separately confirm
`ARCHIVE SUCCEEDED`, `Archive exempt-encryption declaration verified`,
`EXPORT SUCCEEDED`, and `UPLOAD SUCCEEDED with no errors` on October 29, 2026
at 07:57 UTC.

Apple subsequently reported **VALID**, not expired,
`usesNonExemptEncryption=false`, internal **IN_BETA_TESTING**, and external
**READY_FOR_BETA_SUBMISSION**. The build was read back from **Owner Testing Auto**
with automatic distribution still enabled, no public link, and exactly the
same single owner. **No manual build-to-group assignment was performed** for
1.0.5. No external review or external distribution was started.

Use the direct **Ask Duo** sparkle icon, explicitly read/review/approve an excerpt,
then ask Apple Intelligence. Supported hardware with Apple Intelligence enabled
and its model downloaded is required for actual generation. CI verified the
real framework compiled, private/consent/filtering safeguards, unavailable
model handling and confirmed navigation, but did not generate a live model
answer. Phone installation and live-model acceptance remain owner checks;
there is no alternate provider or fake-answer fallback.

### Verified reading and start-page acceptance

[Run 40845914100](https://github.com/ErrantActions/Duo-Browser/actions/runs/40845914100)
passed **three focused UI tests with zero failures** for commit
`205fd3deb10967a41aeffc71d82e2cec43863e23`.
The existing favorite-save/open flow passed on the redesigned home screen.
Reading tests verified actual article extraction, Sepia selection, text-size
increase, persistence after reopening, native PDF share presentation without
an export error, share dismissal, and preservation of the original Record 2
page state. Private reading/export confirmation could be canceled without
sharing; Ask Duo remained disabled in the private tab.

The simulator did not certify audible speech output, every share destination,
or physical-device layout. Native PDF unit tests separately inspect generated
pages and searchable text. The focused run is not a claim that the full UI
suite passed.

The page-tool refactor was separately checked in
[Ask Duo run 40851770098](https://github.com/ErrantActions/Duo-Browser/actions/runs/40851770098),
which passed two UI tests with zero failures for commit
`fd21c43b7d25cbd7cdbd99283e7ac9845834759f`.
It reported the model unavailable and did not generate an answer; consent,
field filtering, private exclusion and confirmed HTTPS navigation passed.
An earlier simulator run reported ready but generation returned an untyped
NSError (-1). Safe error-domain/underlying-code diagnostics and explicit
failure UI were added; no successful live-model result is claimed.
Eligible physical-device generation remains an acceptance check, not a
green result inferred from the unavailable-model regression.

### Verified reading/polish delivery: version 1.0, build 1.0.6

[Run 40856101620](https://github.com/ErrantActions/Duo-Browser/actions/runs/40856101620)
delivered commit `1af70ea2c662ef1e9c1a2291268868b1b3e6d398`.
All **79 native unit tests** passed with zero failures, including six reading
tests for structured/bounded content, actual paginated/searchable PDF output,
query-metadata omission, old settings migration, reader preferences, capability
suspension and stopped speech state. The earlier reading/home acceptance passed
three UI cases; the separate AI-boundary regression passed two without claiming
live inference. Neither suite was duplicated in the signed job.

Preflight selected **1.0.6** above existing uploads. Logs separately verify
`ARCHIVE SUCCEEDED`, `Archive exempt-encryption declaration verified`,
`EXPORT SUCCEEDED`, and `UPLOAD SUCCEEDED with no errors` on October 29, 2026
at 10:33 UTC. An earlier attempt passed tests/archive/export but timed out on a
final read-only Apple metadata check before upload. Bounded GET retry contracts
were added and tested; no upload was blindly repeated.

The version-filtered build listing initially lagged. App Store Connect showed
the upload complete, then the direct build resource
`929537a0-1f1d-41e2-ba35-6d68b9b2ec3b` verified **VALID**, not expired,
`usesNonExemptEncryption=false`, internal **IN_BETA_TESTING**, and external
**READY_FOR_BETA_SUBMISSION**. The build was read back from **Owner Testing Auto**
with exactly the same one owner, automatic access enabled and no public link.
No manual group assignment or external review submission was performed.
English What to Test notes describe the features and remaining device checks;
existing owner notes in other languages were preserved.

This is a substantial tested feature/polish iteration, not certification that
the app is perfect, all Safari features exist, speech was heard, every sharing
destination succeeded, or Apple Intelligence produced a live answer. Those
remaining physical-device checks are explicitly retained.

### Verified direct Ask Duo control

[Run 40905306756, attempt 2](https://github.com/ErrantActions/Duo-Browser/actions/runs/40905306756/attempts/2)
passed **two focused native UI tests with zero failures** for commit
`ff97d7a77ac993af1b32a969b16520b7cbd288d4`.
The Ask Duo sparkle icon measured x=399, y=231, width=38, height=38 in a
466-point window, remained hittable with all eight website controls installed,
and existed exactly once. The menu collection contained no Ask Duo duplicate.
It opened the existing assistant without implicit capture, returned to the
unchanged Record 2 page, and retained private-tab blocking.

The full native toolbar regression also passed: safe viewport 382-by-620 in a
466-by-678 window, no overlapping native buttons, page-matching light/dark
backgrounds, connected URL bubble open/close/validation, website navigation,
refresh/clear, and ordinary HTTPS navigation. An earlier attempt's external
page loading wait timed out; the unchanged job was rerun without loosening
assertions or changing browser network behavior. No live model inference
was required or claimed for this entry-point-only change.

### Verified direct Ask Duo delivery: version 1.0, build 1.0.7

[Run 40910443054](https://github.com/ErrantActions/Duo-Browser/actions/runs/40910443054)
delivered commit `46aa7af7c2c89ae2a9045088319b7efbcd2287af`, with the same
application code as the direct-control UI acceptance above. All **79 native
unit tests** passed with zero failures. Preflight chose **1.0.7** above existing
uploads, and logs separately confirm `ARCHIVE SUCCEEDED`,
`Archive exempt-encryption declaration verified`, `EXPORT SUCCEEDED`, and
`UPLOAD SUCCEEDED with no errors` on October 29, 2026 at 16:38 UTC.

Apple initially did not expose the new build in its listing. Without a duplicate
upload or manual assignment, it subsequently appeared in **Owner Testing Auto**
as **VALID**, not expired, `usesNonExemptEncryption=false`, internal
**IN_BETA_TESTING**, and external **READY_FOR_BETA_SUBMISSION**. The group still
has automatic access enabled, exactly the same one owner and no public link.
English What to Test notes describe the direct sparkle icon and unchanged
consent/private protections. No external review or additional tester was added.

The icon opens Ask Duo in one tap on ordinary and DuoKit pages; opening does
not capture content or bypass model availability/private-tab restrictions.
The backend was not changed and live generation is not claimed by this
entry-point-only validation. Actual phone installation remains unverified.

After an upload:

1. Confirm archive, export, and delivery success separately.
2. Wait for [Apple processing](https://appstoreconnect.apple.com/apps/6827739657/testflight).
3. Let the owner resolve compliance/legal prompts.
4. Confirm automatic delivery to **Owner Testing Auto**, with only the owner
   included. No per-build manual assignment is required for future eligible
   uploads. No public links or external testers without approval.
5. Install through Apple's TestFlight app and confirm actual launch, browsing,
   native panel permissions, and scanning on a supported physical phone.

Delivery is not proof of completed processing or phone installation. Do not
repeatedly upload solely because Apple has not displayed a build yet.
