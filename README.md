# Duo Browser

A native SwiftUI iPhone browser using Apple WebKit, with website-configurable
**Duo Controls** rendered in a native **Duo Panel**.

| Surface | Name |
| --- | --- |
| iPhone application | **Duo Browser** |
| Website SDK | **DuoKit** |
| JavaScript SDK | `duo.js` |
| Web API | `window.duo` |
| Native website control pane | **Duo Panel** |
| Site integrations | **Duo Controls** |
| Developer documentation | **Duo Web API** |

## Requirements and status

- iOS 17+, iPhone, Xcode 27.1+ on macOS; no third-party app dependencies.
  The native Duo toolbar is availability-gated to iOS 27.1; older iOS versions
  retain ordinary browsing and a separate website-control sheet.
- Source implements browser navigation, regular/private tabs, bookmarks, history,
  downloads, settings, DuoKit 1.0, native panels, and permission-gated scanning.
- Created on Windows, where Xcode and Apple simulators are unavailable.
  The macOS [CI workflow](.github/workflows/ios.yml) builds and runs simulator
  tests after publication. This repository starts from a cleaned source snapshot
  with one initial commit, not a fork or a copy of prior Git history.
  The first successful release passed all 61 native unit tests on Xcode 27.1.
  Full UI acceptance remains separate and is not claimed by the upload result.
  The native Duo toolbar correction passed its focused simulator UI test:
  the webpage retained 382 of 466 points of width and site actions appeared
  in the slim native strip to its right. This is not a half-screen split.
- Both workflows are **manual only**, using the documented standard `xcode-27`
  public runner with Xcode 27.1/iOS 27.1 selected explicitly. Standard public
  compute is free; larger runners can be billed and are not selected here.
  Optional artifacts contain sanitized test counts only and expire after one day.
- The existing App Store Connect listing is **DuoKit**, with **Duo Browser** as
  the installed app name. Version **1.0 (1)** was signed, exported, and
  successfully uploaded on October 28, 2026 in
  [release run 40795353458](https://github.com/ErrantActions/Duo-Browser/actions/runs/40795353458).
  Apple processing of build 1 is verified **VALID**, and a subsequent Apple
  lookup shows its export-compliance answer recorded. Build assignment and
  phone installation are not independently verified here.
  The corrected native Duo toolbar is in **build 1.0.1**, successfully uploaded in
  [release run 40803693515](https://github.com/ErrantActions/Duo-Browser/actions/runs/40803693515)
  after 62 passing native unit tests and the focused toolbar UI test. Apple had
  not yet listed that new build at the immediate post-upload check; processing
  and installation of 1.0.1 remain unverified. Build 1 has the older layout.
- Physical-device scanning and the manual browser checklist below require
  additional validation. This is not an App Store-ready Safari replacement.

## Build, run, and test

1. Open [DuoBrowser.xcodeproj](DuoBrowser.xcodeproj) on a Mac.
2. Select the **DuoBrowser** scheme and an iPhone simulator with iOS 17+.
3. Run with Command-R; run tests with Command-U.
4. For a physical device, choose your development team. The approved app
   identifier is `com.errantactions.duobrowser`; use your own identifier for
   an independent fork.

Command-line build:

```sh
xcodebuild -project DuoBrowser.xcodeproj -scheme DuoBrowser \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

List available simulators, then replace `SIMULATOR_UUID`:

```sh
xcrun simctl list devices available
xcodebuild -project DuoBrowser.xcodeproj -scheme DuoBrowser \
  -destination 'platform=iOS Simulator,id=SIMULATOR_UUID' \
  CODE_SIGNING_ALLOWED=NO test
```

Cross-platform checks (Node.js 22+ and Python 3.11+, no third-party packages):

```sh
node --test Tests/*.test.cjs
python -m unittest discover -s Tests -p "test_*.py"
node Tests/validate-project.cjs
```

Manual GitHub simulator validation:

```sh
gh workflow run ios.yml --repo ErrantActions/Duo-Browser --ref main \
  -f confirm_run=true -f save_summary=false
```

TestFlight uploads run the security checks and all native unit tests; the slower
UI suite remains in the separate full validation workflow. Its signing preflight checks
credentials/profile/entitlements and selects a build number above Apple's
existing uploads before compilation. See [secure TestFlight steps](Documentation/TESTFLIGHT.md).
An uploaded owner-only beta is not proof of a passing UI suite.

## Using the browser

In native Duo vertical-toolbar layouts, the address is a compact **Address and
search** button in the edge strip. Tap it to edit the full URL or search, then
choose Go; Cancel leaves the webpage untouched. There is no duplicate bottom
address/navigation bar in this mode. Browser Back, Refresh/Stop, Tabs, and Menu
remain in the edge controls; Forward and Share are available through the menu.
The host caption and accessibility value identify the page and private/connection
state. Website-specific controls appear only for approved DuoKit sites.

Elsewhere, enter an address or search phrase in the normal bottom address bar.
Focus it to edit the full URL. The toolbar provides back, forward, share, tabs, and a menu for
bookmarks, history, downloads, find, desktop/mobile preference, page information,
settings, and permissions. Pull down a webpage to refresh.

The browser follows the system's actual `toolbarVerticalEdge` inside its native
navigation container, not a guessed screen width. The webpage fills the remaining
safe viewport; it is not extended behind the native controls with ignored safe areas.

Settings include search engine, custom startup page, session restore, maximum
tabs (default 20, range 1–100), history retention (default 30 days), appearance,
website camera/microphone blocking, and default Duo permissions.
Save settings explicitly. A blank startup URL uses the local start screen.
When enabled, session restoration takes priority over the startup page.

The tab button opens a familiar two-column preview grid. Tap a card to return
to its page, use its corner close button, or use **+** to open a tab.
**Tabs / Private** switches between separate sessions; **Search Tabs** filters
page titles and addresses. The selected card is outlined. Larger accessibility
text switches the grid to one column rather than squeezing controls.

**Close All** asks before closing the current regular/private session; tabs in
the other session are preserved. **Recently Closed Tabs** is available from the
browser menu and by holding **+** in the overview. It includes regular pages only,
stays in memory for this launch, and is bounded by the maximum-tab setting.
Reopening uses a fresh web view with the saved address, zoom, and desktop/mobile
preference; private pages, forms, and old back/forward stacks are not restored.

Previews come from each tab's existing WebKit view, stay only in memory, and are
discarded when the card leaves the overview or the app becomes inactive.
An offscreen page that WebKit cannot capture is labeled **Preview Unavailable**;
no fake webpage preview is substituted. Private previews never enter storage.

Each tab owns its WebKit instance. Switching ordinary controls and the Duo
Panel does not replace the webpage. Regular tabs restore URLs and desktop
preferences after relaunch; WebKit back/forward, form, and scroll state are kept
in memory while a tab is alive, not serialized to disk. A restored address is
preserved even if the app saves its session before WebKit publishes the URL.

Private tabs use a separately managed nonpersistent website store and are never
saved in session restore or history. Closing the final private tab discards that
private session's store. Private mode does not hide traffic from websites or
network providers. Bookmarks and explicitly downloaded files remain saved even
when created from a private tab; private download records are not persisted.

### Favorites, bookmarks, history, and Reading List

The start page has a native favorites grid and direct links to the library.
**Add Bookmark** opens an editor for the title, address, folder, and **Show on
Start Page** favorite switch. Bookmark collections filter all bookmarks,
favorites, unfiled bookmarks, or a named folder; search matches the title,
address, and folder. Favorites use local monograms rather than contacting
websites to fetch icons. Existing bookmarks remain readable and are not
automatically made favorites.

History groups visits by local calendar day, newest first, with search,
individual deletion, and confirmed clearing. Bookmarks, history, and Reading
List support opening in a new tab in the current regular/private session.

**Add to Reading List** stores a link for later; its list supports search,
read/unread filtering, explicit mark-read/unread actions, deletion, and sharing.
Resaving a link updates its existing entry and marks it unread. These are local
saved links, **not offline article downloads or Reader mode**. Explicitly saved
bookmarks, favorites, and Reading List entries persist even when saved from a
private tab, and remain when browsing data is cleared.

Bookmark and Reading List writes report failures without closing the editor or
applying an unsaved change. New optional saved-data fields preserve compatibility
with older library snapshots; malformed fields still surface a storage error.

### Page zoom

The browser menu's Page section provides zoom out, zoom in, and a percentage
button that resets to 100%. Native WebKit zoom ranges from 50% to 300% and does
not reload the page. Zoom is per tab, retained when switching tabs, and saved
with regular-tab session restoration; it is not a synced per-website preference.

### Managing downloads and browsing data

Downloads show progress when WebKit provides it. Cancel waits for WebKit to
stop the transfer before removing its incomplete file. Interrupted regular
downloads are marked failed on the next launch, and their saved partial files
are removed where possible; cleanup failures are reported in Downloads.
Completed files remain available through **Open or Share** and **Preview File**.
Preview uses iOS Quick Look for supported formats, with the original filename
and a native Done action. Unsupported formats or missing files produce an
explicit error; opening a preview does not grant a website file access.

Swipe a stopped download and choose **Delete**, then confirm deletion of both
the entry and its file. Cancelling must finish before an entry can be deleted.
Missing files do not prevent removing stale entries. Suggested names are
stripped of path components and bounded by UTF-8 bytes, including long Unicode
names; download locations cannot be supplied by a website.

**Clear Browsing Data** closes tabs, persists an empty restored session, waits
for active downloads to stop, and then clears website storage/history/Duo
decisions. Opening tabs is blocked during cleanup. Afterwards the built-in
start screen opens without contacting your configured custom start page.
Bookmarks, Reading List, settings, and completed downloads are preserved.
The in-memory recently closed tab list is cleared.

### DuoKit demo

On the built-in start screen tap **Explore DuoKit Demo**, or select **DuoKit
Demo** from the browser menu. Tap **Install Duo Panel**, then grant the site's
Duo Controls permission. On iOS 27.1, real SwiftUI toolbar items request the
native vertical presentation used by iPhone Duo. They form a slim display-edge
strip rather than a half-screen panel or extra buttons inside the URL bar.
SwiftUI chooses the edge and presentation for the current device pose/locale;
other contexts can use native horizontal toolbar presentation.

The native strip has browser **Back** and **Refresh/Stop**, then the website's
own navigation and special actions. Try **Previous Record** and
**Next Record** to change the demo's content without navigating away; also try
the scan/action buttons, toggle, segments, menu, and confirmed primary action.
The webpage logs events. **Update Duo Controls** replaces the site's complete
configuration; **Clear Duo Panel** removes its toolbar items. **All Website
Controls** opens a labeled sheet with the full controls and badges; option
controls use native menus in the slim toolbar. On older iOS versions,
**Duo Controls** launches that sheet directly. **Hide Duo Controls** dismisses
site controls without navigating; **Show Duo Panel** in the browser menu
restores them. Ordinary sites receive no empty side pane or site toolbar.
The core browser edge controls and collapsed address remain available on
ordinary sites when the system uses a vertical bar.

Tap the native **Scan** control to request scanner permission. On supported
physical iPhones, iOS then requests camera access and displays a live scanner.
The simulator reports scanning as unavailable; it does not invent a result.

The bundled demo can also be opened in an ordinary browser from
[its HTML file](DuoBrowser/Resources/Demo/index.html); HTML fallback controls work
without DuoKit. The demo has no analytics or network calls of its own.

## Documentation

- [Architecture](Documentation/ARCHITECTURE.md)
- [Duo Web API 1.0](Documentation/DUO_WEB_API.md)
- [Bridge and scanner security model](Documentation/SECURITY.md)
- [Owner-only TestFlight publishing](Documentation/TESTFLIGHT.md)

## Verification

Automated suites cover URL normalization/search, schema rejection, size/count
limits, icons/types, private history/session exclusions, tab identity/limits,
exact-origin permission persistence, rate limiting, and the JS SDK.
Additional regression tests cover saving still-loading restored tabs,
late callbacks to closed tabs, serialized data clearing, download filename byte
limits, interrupted-file cleanup, deletion containment, and private download
record exclusions.
Further tests cover old saved-data decoding, favorites/folder filtering, write
rollback, Reading List state, calendar-day grouping across daylight-saving
changes, recently closed/private exclusions, bulk tab closing, page zoom, and
Quick Look data-source wiring. The existing native run passed all 61 unit tests.
The UI tests cover demo permission, event delivery, panel clearing,
tab creation/closing, regular/private grid switching, selection preservation,
an ordinary HTTPS address, and back/forward navigation.
The existing run passed the panel/tab-grid UI cases. Its favorite and HTTPS
cases failed an external page-heading assumption; the corrected assertions
still need an approved native rerun. No all-green native suite is claimed.
CI boots one simulator explicitly and runs the native suites sequentially.
Optional artifacts contain whitelisted test counts only; raw result bundles,
screenshots, and signing files are not uploaded. The new release contracts have
19 passing Node tests and 3 passing Python tests locally. Actual profile/API/
archive validation still requires privately configured secrets and an approved job.
Do not equate project syntax checks or SDK tests with
successful iOS compilation or runtime acceptance.

Manual simulator/device acceptance checklist:

- Ordinary HTTPS sites, links, input focus, text selection/paste, scrolling,
  back/forward/swipe navigation, reload/stop, progress, and pull-to-refresh.
- Offline/retry behavior and invalid certificates (no bypass).
- New-window links, JavaScript alerts, both confirm outcomes, and
  empty/cancelled prompts.
- Share sheet, find, desktop/mobile preference, persistent bookmarks/history,
  downloads/progress/cancel/open/share/delete, startup configuration and restoration.
- Favorites save/edit/remove and folder/search filters; old library migration;
  Reading List read/unread/resave; day-grouped history around midnight.
- Reopen/forget regular closed tabs, private exclusions, confirmed close-all,
  tab-limit behavior, zoom restore, and supported/unsupported Quick Look files.
- Clear data during an active transfer: verify no new tab opens during cleanup,
  the transfer stops, history/session do not reappear, completed files remain,
  and the custom start website is not contacted automatically.
- Private cookie/session isolation and exclusion from history/restore.
- Demo install/update/clear, all control types, deny/grant/revoke, cross-origin
  navigation clearing, and separate panel state across tabs.
- On a physical supported iPhone: camera denial/grant, scan result, cancel,
  timeout, backgrounding, duplicate suppression, navigation/tab changes, and
  permission revocation while scanning.
- Small/large iPhone, portrait/landscape, light/dark, VoiceOver, large text.

## Safari-like feature coverage

This is **source implementation coverage, not verified feature parity**.
The newest native features still need compilation, simulator checks, and
physical-device testing. Public WebKit APIs cannot reproduce every Safari
system integration.

| Area | Implemented in Duo | Important gaps |
| --- | --- | --- |
| Browsing | URL/search, navigation, dialogs, sharing, find, mobile/desktop preference, native zoom | Reader extraction, page translation, full popup/window semantics |
| Tabs | Regular/private sessions, preview grid, search, close-all, recently closed pages, URL/zoom restore | Tab groups, pinned tabs, complete session-stack serialization, cross-device tabs |
| Saved pages | Favorites, bookmark editing/folder filters, local Reading List/read state | Offline Reading List articles, bookmark import/export, cloud synchronization |
| History | Local day groups, search, deletion, retention, private exclusions | Synced browsing history |
| Downloads | WebKit progress/cancel, partial-file cleanup, deletion, native preview/open/share | Resume and guaranteed background transfers |
| Site controls | Origin-scoped DuoKit panels, permissions, native scanner | Physical-camera and full permission-flow validation |
| System features | Ordinary WebKit behavior and native sharing/preview interfaces | Safari extensions, iCloud Safari integration, custom credential manager, default-browser entitlement |

## Known gaps compared with Safari

- No full WebKit session serialization: restored tabs start new navigation stacks.
- Popup links open a new tab, but JavaScript-created popup windows do not retain
  Safari's full opener/window-object behavior.
- No download resume or background download guarantees,
  credential/password manager, browser extensions,
  reader mode, syncing, content blocker, or default-browser entitlement.
- WebKit may ignore desktop content preferences on some sites.
- Website location permission remains controlled by WebKit/iOS. Duo has no
  custom per-origin permission manager for every web platform capability.
- HTTPS is a transport indicator, not an endorsement of a site's identity.
- Clear Browsing Data removes website storage/history/Duo decisions and closes
  tabs, but preserves bookmarks and explicit downloaded files. OS permissions
  such as Camera must be revoked separately in iOS Settings.
- The original compass app icon uses a continuous-screen phone silhouette in an
  upright, book-open pose. Its editable vector
  source is [DuoBrowser.svg](Design/DuoBrowser.svg). It uses no Apple artwork.
  Distribution signing and App Store review have not been done.
- Older bookmark, Reading List, and zoom fields have backward-compatible
  decoding, but there is no general versioned migration/recovery UI. Corrupt
  storage is reported and protected from overwrite rather than silently erased.
- The privacy manifest describes Duo's code, not the practices of websites users
  visit. Review all declarations and distribution requirements before release.
