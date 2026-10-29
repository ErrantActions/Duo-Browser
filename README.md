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
  The edge-only update also passed [focused UI run 40807358107](https://github.com/ErrantActions/Duo-Browser/actions/runs/40807358107):
  a 382-by-620-point webpage in a 466-by-678-point window, no duplicate
  bottom chrome or overlap with edge buttons, and working address expand,
  Cancel, and Go. That focused pass is not a claim that the full UI suite passed.
  The two-stage address bubble and unique core controls passed
  [focused UI run 40813672395](https://github.com/ErrantActions/Duo-Browser/actions/runs/40813672395):
  one address field and on-screen keyboard on the first tap, then the same
  icon opening the full editor with the typed draft preserved.
  The connected **URL** toggle and live rail colors passed
  [focused UI run 40820895631](https://github.com/ErrantActions/Duo-Browser/actions/runs/40820895631).
  Screenshot samples exactly matched both light and dark CSS backgrounds on
  the page, across the seam, and behind the outer controls. A second URL tap
  closed the bubble without opening a larger window.
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
  after 62 passing native unit tests and the focused toolbar UI test. A subsequent
  Apple lookup verified 1.0.1 as **VALID**, not expired, with its compliance
  answer recorded; phone installation remains unverified. It still has the
  duplicate bottom chrome removed by the current edge-only source update.
  That edge-only update was successfully signed, exported, and uploaded as
  **build 1.0.2** in [release run 40808360983](https://github.com/ErrantActions/Duo-Browser/actions/runs/40808360983)
  after **63 passing native unit tests**. Apple processing is verified **VALID**.
  Its beta state is **MISSING_EXPORT_COMPLIANCE**: the owner must answer that
  Apple prompt truthfully before distribution. No answer was invented or copied
  automatically. Assignment and phone installation remain unverified.
  The earlier two-stage address bubble and unique controls were delivered in
  **build 1.0.3**, [release run 40814804265](https://github.com/ErrantActions/Duo-Browser/actions/runs/40814804265),
  after the focused UI pass and **63 passing native unit tests**. Apple processing
  is **VALID**; this build also needs the owner's export-compliance answer before
  distribution. That build used first-tap inline typing and second-tap full
  editing; the latest release below replaces the second tap with closing.
  **Build 1.0.4** delivers the matching rail background, bounded **URL**
  label, and connected open/close bubble in
  [release run 40823535016](https://github.com/ErrantActions/Duo-Browser/actions/runs/40823535016).
  All **64 native unit tests** passed. The owner-confirmed exempt-encryption
  declaration survived the signed archive; Apple reports **VALID**,
  `usesNonExemptEncryption=false`, and **READY_FOR_BETA_TESTING** without a
  compliance questionnaire. The new **Owner Testing Auto** internal group now
  has automatic distribution enabled, exactly the same single owner, and no
  public link. Build 1.0.4 is verified in that group as **IN_BETA_TESTING**.
  Future eligible uploads no longer require manual group assignment.
  Actual phone installation remains unverified. The original manual group was
  preserved; no France/store-territory setting was changed.
- **Build 1.0.5** includes **Ask Duo**, powered by Apple's on-device
  Foundation Models, delivered in
  [release run 40837364527](https://github.com/ErrantActions/Duo-Browser/actions/runs/40837364527)
  after **72 passing native unit tests** and the separate focused UI acceptance
  below. Apple processing is **VALID**, encryption compliance was accepted, and
  the build appeared in **Owner Testing Auto** as **IN_BETA_TESTING** without
  manual group assignment. Live answer generation still needs checking on an
  eligible device because CI reported the on-device model unavailable.
- Ask Duo's Apple Foundation Models integration compiled and passed
  [focused native run 40835752864](https://github.com/ErrantActions/Duo-Browser/actions/runs/40835752864):
  two tests, zero failures, covering private-tab exclusion, explicit excerpt
  approval, filtered form/editable content, keyboard interaction, unavailable
  model handling, native confirmation/cancellation, and actual HTTPS navigation.
  The simulator reported its model unavailable; this is **not** a claim that
  Apple Intelligence generated a live answer. That requires an eligible,
  enabled device.
- **Latest: build 1.0.6** delivers the redesigned start page, local Reading View,
  persistent reading themes/type size, Read Aloud controls, paginated reading
  PDF sharing and bookmark keyboard fixes through
  [release run 40856101620](https://github.com/ErrantActions/Duo-Browser/actions/runs/40856101620).
  All **79 native unit tests** passed, including actual PDF page/searchable-text
  checks and old-settings migration. Apple reports **VALID** and
  **IN_BETA_TESTING**, with encryption accepted and automatic delivery to the
  same owner-only group. English TestFlight testing notes were added.
  Voice output, live AI generation and physical-phone installation remain
  device checks; this release is not a claim of perfection or complete Safari
  parity.
- Physical-device scanning and the manual browser checklist below require
  additional validation. This is not an App Store-ready Safari replacement.
- The Reading View/start-page upgrade passed
  [focused native run 40845914100](https://github.com/ErrantActions/Duo-Browser/actions/runs/40845914100):
  three tests with zero failures for favorite saving/opening, reading theme
  and font persistence, real PDF sharing/dismissal, original Record 2 retention,
  private-export cancellation, and continued private-tab AI exclusion.
  Audible speech output remains a device acceptance check.
- The shared page tools also passed
  [Ask Duo regression run 40851770098](https://github.com/ErrantActions/Duo-Browser/actions/runs/40851770098):
  private-tab protection, excerpt approval/filtering, unavailable-model handling
  and confirmed navigation remained intact. Live generation is still not
  certified: another simulator run reported ready but returned an untyped
  model-service error. The app now surfaces safe failure categories rather
  than hiding this condition or substituting a response.

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

### Reading View and reading PDFs

The browser menu's **Page Tools** brings **Reading View** and **Find on Page**
together. **Ask Duo** has its own sparkle icon in the native control strip.
Reading View creates a local, text-only snapshot with headings, paragraphs,
lists, quotes, and code. Choose Paper, Sepia, or Night and adjust text size;
these preferences persist without changing the original page.

**Read Aloud** uses the system speech synthesizer, with pause/resume and stop.
It starts only after a tap and stops when the reader closes or the app becomes
inactive. Actual voice output still requires a device check.

**Share Reading PDF** creates a searchable, paginated PDF of the reading text,
not a full-fidelity copy of the webpage. It uses a generic temporary filename,
omits URL-query metadata, and cleans the protected export after sharing or
cancellation. Private reading stays local; exporting from a private tab asks
for an additional confirmation because another app may retain its own copy.

Forms, editable/hidden text and frames are excluded. Extraction is capped at
30,000 characters and 400 blocks, with an explicit shortened-snapshot notice.
This is not offline Reading List storage, translation, or Safari's proprietary
Reader engine.

The start page has a new adaptive card layout, original gradient hero, richer
favorite tiles and a distinct private palette. No remote favicon requests,
background tracking calls, or second URL/navigation bar were added.

### Ask Duo

Tap the **Ask Duo** sparkle icon directly in the native Duo controls.
Other layouts have the same direct icon in their browser toolbar. It uses **Apple Intelligence's
on-device Foundation Models**, not OpenAI, Copilot, a cloud fallback, or an API
key. Generation requires iOS 26+ on a supported device with Apple Intelligence
enabled and its model ready. The browser still supports iOS 17.

Nothing is read automatically. Choose **Read This Page**, review the filtered
excerpt using **Show Page Excerpt**, choose **Use This Excerpt**, enter a question,
choose **Done Typing**, and choose **Ask Apple Intelligence**. The excerpt is
limited to 1,800 characters and up to 12 HTTPS link labels, so it is not a full
copy of a long page. Forms, editable/input values, hidden content and frames are
excluded; other visible text can still contain personal information.
The model receives the page origin and link labels, not current-URL query or
href metadata. Visible page text can itself contain URLs or private information.
The preview remains local even if Apple Intelligence is unavailable.

**Allow a link suggestion** lets the model propose an existing page-link ID.
It cannot invent a navigation destination or run page code. Opening any
captured or suggested link requires a native confirmation showing its full
destination. The page/document/tab is revalidated, the sheet closes, and only
then does normal HTTPS navigation occur.

Private tabs are excluded. Closing, backgrounding, changing the page, or
changing tabs cancels work and clears the excerpt/question/answer. Nothing is
saved as chat history. There is no arbitrary clicking, form submission,
purchase automation, image analysis, or Duo Control execution in this first
version. AI can be wrong: verify its answer against the page.

There is exactly one Ask Duo launcher in each layout, not a second menu entry.
The icon remains available on ordinary and DuoKit websites, and private tabs
open an explanatory blocked state rather than reading their content.
Real on-device inference must be checked on eligible hardware; a
simulator showing unavailable is not proof that the model generated an answer.

### Address and navigation

In native Duo vertical-toolbar layouts, the address button is labeled **URL**,
not the potentially long hostname. Tap it to expand a connected, editable bubble;
enter an address/search and press Go. Tap **URL** again to close it without
navigation. It does not open a larger address window. Tapping the webpage outside
the bubble also dismisses it without activating the page. There is no duplicate bottom
address/navigation bar in this mode. Browser Back, Refresh/Stop, Tabs, and Menu
remain in the edge controls; Forward and Share are available through the menu.
There is one address icon, not a second full-editor launcher. Browser navigation
is not repeated in the website toolbar in horizontal layouts either.
The accessibility value still identifies the actual host and private/connection
state. Website-specific controls appear only for approved DuoKit sites.

Elsewhere, enter an address or search phrase in the normal bottom address bar.
Focus it to edit the full URL. The toolbar provides back, forward, share, tabs, and a menu for
bookmarks, history, downloads, find, desktop/mobile preference, page information,
settings, and permissions. Pull down a webpage to refresh.

The browser follows the system's actual `toolbarVerticalEdge` inside its native
navigation container, not a guessed screen width. The webpage fills the remaining
safe viewport; only its WebKit-reported background color extends behind the
native controls. Web content and hit targets do not extend under those buttons.
The demo's **Toggle Page Background** exercises live light/dark color updates.

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
saved links, **not offline article downloads**. Reading View is a separate local
snapshot tool. Explicitly saved
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
Quick Look data-source wiring, and address-editor capability isolation during
scene reactivation. Ask Duo adds context/action bounds, unsafe-link rejection,
prompt-metadata filtering, approval/data clearing and assistant lifecycle guards.
The latest release passed all 79 native unit tests.
The UI tests cover demo permission, event delivery, panel clearing,
tab creation/closing, regular/private grid switching, selection preservation,
an ordinary HTTPS address, and back/forward navigation.
The existing run passed the panel/tab-grid UI cases. Its favorite and HTTPS
cases failed an external page-heading assumption; the corrected assertions
still need an approved native rerun. No all-green native suite is claimed.
CI boots one simulator explicitly and runs the native suites sequentially.
Optional artifacts contain whitelisted test counts only; raw result bundles,
screenshots, and signing files are not uploaded. The local checks have
33 passing Node tests and 4 passing Python tests. Actual profile/API/
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
| Browsing | URL/search, navigation, dialogs, sharing, find, mobile/desktop preference, native zoom, local Reading View, read aloud, reading PDF | Page translation, full-fidelity offline articles, full popup/window semantics |
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
