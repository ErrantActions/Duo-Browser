# Duo Browser trust boundaries

This documents implemented policy, not a claim of independent security review
or complete resistance to WebKit/OS vulnerabilities.

## Untrusted website boundary

- WebKit renders websites; no new rendering engine or certificate bypass exists.
- HTTPS main-frame origin is read from WebKit's frame/security-origin metadata
  and compared with the receiving web view's current origin. A message's claimed
  origin is never accepted. HTTP and iframes cannot access Duo capabilities.
- The sole file-origin exception is the exact bundled demo document. Entered
  file paths, file URLs elsewhere, data URLs, and executable URL schemes are
  not browser navigation targets.
- `WKScriptMessageHandlerWithReply` receives only a fixed versioned method
  catalog. Unknown fields/methods, malformed shapes, oversized messages,
  unsupported icons/control types, duplicate IDs, and wrong types are rejected.
- Envelope size is 32 KiB after JSON serialization. This bounds accepted
  configuration, not WebKit's underlying IPC allocation; a hostile page can
  still consume web-process resources. Payload nesting and collection counts
  are bounded. Rate is 20 requests per 10-second sliding window per tab.
- Websites supply only declarative values. There are no native selector,
  reflection, executable Swift, arbitrary file, URL-launch, clipboard, or
  unrestricted system-action methods.
- Native event data is JSON-encoded before JavaScript evaluation. Document IDs
  scope delivery so a subsequent SDK instance ignores a previous document's event.

## Authorization and lifecycle

Normal permissions are local decisions keyed by exact canonical HTTPS origin;
subdomains and ports are distinct. Defaults ask. Users can explicitly choose
different defaults in browser settings. Private tab decisions are not persisted.

Each tab owns its bridge, current panel, document ID, generation, limiter,
permission completion, and one-use native activation token. It cannot mutate
another tab's bridge. Every main navigation clears document-owned state.
Stored grants can reauthorize only a fresh valid configuration from the new
document. Pending permission/scanner work cannot complete against a different
navigation generation, origin, document ID, or tab.

Switching tabs/backgrounding dismisses camera work, settles pending permission
requests, cancels website dialogs, and pauses page media. Closing a tab also
removes message handlers/scripts and delegates. Weak proxies and captures avoid
retaining closed views through WebKit.

Revocation immediately clears matching panels, activation tokens, pending
permissions, and scans in open tabs. The OS Camera permission is separate and
must be changed in iOS Settings.

## Native interface

Native controls always appear below immutable browser address UI with explicit
website attribution and a Browser escape button. Labels remain visible;
overflow scrolls rather than disappearing. Configuration cannot hide native
browser escape UI or customize system permission prompts. Page messages are
presented in explicitly website-labeled sheets, not disguised as iOS alerts.

Optional confirmations identify the website. Appearance/accent choices are a
small catalog, not arbitrary native styling or images. VoiceOver labels and
minimum touch targets are provided; physical-device accessibility review is
still required.

## Scanner

1. A user activates a visible native Duo control.
2. Native code issues a random, single-use token bound to the current bridge
   state, expiring after ten seconds.
3. The webpage explicitly requests scanning with that token and request ID.
4. Duo checks frame/origin/document/tab, consumes the token, and checks its
   separate per-origin scanner permission.
5. Supported hardware and ordinary iOS camera authorization are required.
6. VisionKit displays a live preview and cancel action. First result stops
   scanning; duplicate events are suppressed. Timeout is 60 seconds.
7. Outcome delivery rechecks document, generation, origin, and active tab.

No background scanning or automatic camera grant exists. No photos/video are
saved. Scanned strings are not logged, interpreted as URLs, persisted by Duo,
or forwarded elsewhere. Sites may process the values they explicitly receive.

## Other browser data and permissions

WebKit's normal permission prompts govern ordinary site media. A setting can
deny all website camera/microphone requests; otherwise Duo returns `.prompt`,
never an automatic grant. Location is subject to WebKit/iOS behavior. The Duo
scanner does not bypass camera permission via this website mechanism.

External app links use an allowlist and explicit native confirmation. Automatic
redirects/iframes cannot open other apps. Download destinations are constrained
to an app-controlled directory, with path components removed from suggested
names and UUID prefixes preventing collisions. Opening/sharing a downloaded
file is a separate user action. Names are limited by UTF-8 bytes, not character
count. Stored download paths must be single components matching their download
ID, and sharing rejects directories and symbolic links. Confirmed download
deletion refuses recursive directory removal and retains the record on errors.

Clear Browsing Data persists an empty session before awaiting cleanup, disables
new tabs, ignores callbacks to closed tabs, and waits for active transfers to
stop before removing WebKit website data. The replacement tab uses the local
start screen, even when a custom startup URL is configured, so cleanup does not
silently restart network activity. Bookmarks and completed files are retained.

Library files use atomic writes and iOS file protection. Failed reads do not
silently overwrite corrupt originals. Private website data is nonpersistent;
private history/tabs/decisions/download records are excluded from the library.
User-created bookmarks and explicitly downloaded files persist by design.
Favorites and Reading List entries are also explicit saved data and are shared
between regular/private sessions on this device. The native start page uses
local monograms, not remote favicon requests. Reading List does not fetch
articles in the background or promise offline copies.

Recently closed tabs retain regular page metadata in memory only. Private tabs
never enter that list, and clearing browsing data discards it. Page zoom stores
only a numeric per-tab preference and uses the existing WebKit instance.
Downloaded-file preview uses the same validated file location as sharing; it
does not expose a file-access method through DuoKit.

Structured native logs record only operational failures/codes, not URLs,
browsing content, or scanned values. The demo logs events visibly to its own
page, only in memory, and redacts native gesture tokens from that visible log.
UI tests do not deliberately print the full accessibility hierarchy into public
console logs. Test screenshots/result bundles can still contain the synthetic
demo page, so CI must never browse real accounts or production private data.
There is no analytics or synchronization service.

## Repository and release controls

- Signing/private-key files, local environment files, build output, user-specific
  IDE state, and downloaded test artifacts are excluded by the repository's
  ignore rules. Ignoring a file does not remove tracked history; scan both.
- Actions dependencies are pinned to immutable commit hashes and proposed
  updates are reviewed. Checkout credentials are not persisted.
- CI tokens have read-only contents permission. Unsigned pull-request jobs
  receive no Apple signing environment or signing secrets.
- Repository Actions permissions allow GitHub-owned actions only. Public
  repository secret scanning and push protection are enabled.
- Signing requires manual confirmation on `main`, successful verification, and
  explicit owner approval of the `app-store` environment. Administrator bypass
  is disabled.
- Private signing values are removed from child-process environments before
  native archive tools execute. Temporary keychain/profile/API-key files are
  cleaned up even after failures. Only test results, not signing files or IPA
  exports, are uploaded as artifacts, with three-day retention.
- Local agent/checkpoint refs are not publication branches. Never mirror-push
  local refs or publish local audit backups; they may contain workstation
  identity metadata that is not present in the public branch.

## Adding a native capability

1. Define a narrow versioned request schema; reject unknown fields and bound
   size, nesting, strings, arrays, and rate.
2. Reuse native frame/origin validation and per-tab document/generation checks.
3. Add a separate capability permission, revocation path, and iOS permission
   descriptions where required. Never infer system access from panel approval.
4. Require a fresh native activation token for sensitive actions. A field in
   website configuration or a forged DOM event is not evidence of user action.
5. Keep system actions and file paths under native control. Avoid arbitrary
   selectors, URLs, paths, or APIs exposed through generic dispatch.
6. Add visible native UI, cancellation, timeout, lifecycle cleanup, and a
   narrowly scoped result event. Do not return data after navigation/tab changes.
7. Test malformed messages, wrong origins/frames, replay, revoked permission,
   tab isolation, rate limits, and lifecycle races on a real WebKit instance.
8. Document the API, privacy impact, hardware limits, and fallback behavior.

## Remaining release work

Build/test verification, simulator browser acceptance, physical camera/privacy
flows, accessibility audit, privacy declaration review, app icon and signing,
storage migration/recovery, and an independent pre-release security review are
not replaced by this document or by passing unit tests.
