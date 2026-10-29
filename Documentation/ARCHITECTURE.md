# Duo Browser architecture

## Ownership and UI

### Local reading tools

Reading View reuses the bounded, isolated page-context script with a separate
`reader` mode. It copies plain blocks, not executable HTML or subresources.
`ReaderDocument` rechecks source URL, tab/navigation identity, document UUID,
block types/counts and aggregate text limits. The AI path remains 1,800
characters/private-disabled; local reading permits private tabs without
calling any model. The original WKWebView is retained and never reloaded merely
to open or close the reader.

Reader appearance lives in `BrowserSettings.reader`; older saved settings
decode with safe defaults, and malformed reader settings fail explicitly.
The common page-tool presenter suspends website capability UI for both Reader
and Ask Duo, including scene reactivation and tab-change cleanup.

`ReaderModel` bounds extraction time, stops speech on dismissal/inactivity, and
keeps article text in memory. System speech is explicitly user initiated; no
Personal Voice or background-audio capability is enabled.
`ReadingPDF` draws plain attributed text using Core Text into paginated A4
pages, with progress/page/size guards. A source host is attributed, not URL
queries. Export files are protected, generic-named, and owned by the active
share lifecycle; completion/dismissal removes only the generated UUID folder.
The start page uses native adaptive cards and locally generated favorite
monograms rather than fetching third-party favicons.

### Ask Duo

`AskDuoView` is a browser-owned compact/expandable chat sheet, opened directly by the trusted sparkle
button in the native Duo strip. The nonvertical/legacy browser toolbar has the
same direct action, and the menu does not repeat it. Opening the icon uses the
existing page-tool presenter and does not capture content automatically.
`AskDuoModel` uses an explicit on-device `SystemLanguageModel` and a fresh
`LanguageModelSession` for each question. A bounded in-memory conversation retains
six completed exchanges, supplying only two shortened question/answer pairs as
untrusted JSON context. Native link objects, identifiers and href metadata are
not serialized into conversation history. New Chat resets exchanges; turning
page access off also removes page context and history. `@Generable` constrains the response
to answer text and a bounded existing-link ID; no model tools, JavaScript,
network client, or cloud provider are registered. OS/model availability is
checked and an unavailable state never becomes a sample or fabricated answer.

The model accepts typed availability/generation dependencies for deterministic
state-machine tests. Native UI tests explicitly opt into a visibly labeled
`--ask-duo-ui-fixture` only in DEBUG builds; its scripted responses are not
Apple inference. Release builds exclude this generator and always use the real
Apple provider. A separate native probe first attempts a minimal plain-text
response, then tests the actual general/page response schemas. It explicitly
skips unavailable models or the simulator's known internal `-1` failure on that
minimal probe; it does not convert an application-schema failure into success.
Live inference is not claimed when the probe skips.

General chat starts with page access off and does not invoke the page reader.
`AskDuoContext.js` runs only after an explicit page shortcut, Read This Page,
or Send with page access enabled, in a separate named
`WKContentWorld`. It extracts visible non-form/non-editable text and HTTPS
links with bounded DOM work and no reads of input values, cookies, or storage.
Native decoding revalidates the 32 KiB envelope, source URL, document UUID,
text/link limits, credential-free HTTPS URLs, and contiguous link IDs.
Only origin/title/excerpt/link labels reach the model; native URL-query and
full-href metadata stay in native memory. Visible text can still contain URLs
or private information. Context is untrusted data, not model instructions.

Every context/action is bound to the original tab, exact URL, navigation UUID,
and isolated document UUID. Explicit navigation invalidates the UUID
synchronously, and WebKit navigation callbacks also invalidate it. Before a
confirmed action, the static reader checks that the original document and
visible link still exist. The parent applies the fixed destination only after
sheet dismissal and a final tab/URL/navigation check.

Assistant presentation independently suspends website capability UI, including
across scene reactivation. Capture/link checks have 15-second deadlines and
generation has a 60-second deadline. Cancellation invalidates an operation
token so late results cannot repopulate cleared UI. The sheet clears all
context and conversation on close, inactivity, tab changes, or navigation.
Private tabs block all chat. Loading, error, start, non-HTTPS and insecure pages
block page access, except the exact bundled DuoKit demo; general chat can still
work without page access. No live web search or persistent conversation exists.

### Browser layout

SwiftUI/MVVM, iOS 17+. `BrowserView` owns a `BrowserLibrary` and
`BrowserTabManager`. The selected tab is observed by a dedicated tab view with
stable identity. Each `BrowserViewModel` retains one `WKWebView`, one navigation/UI
delegate, and one `DuoBridge`; switching tabs does not reconstruct these objects.
`WebViewContainer` only embeds the existing view. Its update method never loads
content. A vertical layout reserves separate space for the webpage and the
address field/browser toolbar, so WebKit cannot overlap native control hit
targets. On iOS 27.1, `DuoNativeToolbar` wraps that stable browser content in a
`NavigationStack` and declares actual `ToolbarItemGroup` content with
`.axisBehavior(.verticalPreferred)`. These are native system toolbar items, not
a custom width-triggered half-screen split or an HStack appended to the URL bar.
SwiftUI chooses vertical or horizontal presentation and its locale/device edge.
The content view reads `toolbarVerticalEdge` from **inside** that native
navigation container and passes the resulting layout mode to the browser column.
Vertical mode does not construct the custom bottom chrome at all. It declares
core browser navigation, collapsed address, tabs, and the shared browser menu as
native edge items even on sites without DuoKit. Nonvertical/older layouts retain
the normal bottom chrome.

`BrowserAddressEditor` edits a tab-local draft in a compact bubble.
The native button has a fixed **URL** caption and a 44-point layout box;
the real host/security/private state remain in its accessibility value.
The first tap expands the bubble and focuses the keyboard; the second tap on
the same icon closes it without navigating or opening another sheet.
The toolbar button reports its global frame so the input remains inside the
webpage's safe viewport. Its noninteractive material background extends to
enclose that same native icon; the icon's separate shared-glass background is
hidden while expanded. No second launcher or permanent bottom chrome is created.
The shared URL normalizer validates the draft; submission is applied only after dismissal so external-app
confirmation or navigation errors do not compete with the editor presentation.
Cancel leaves the page intact. Address editing suspends website capability UI
even if scene activation attempts to reactivate the tab; dismissal resumes only
the selected, active tab. The existing WebKit instance and form/scroll state are
preserved.
While the bubble is open, a webpage tap dismisses it without delivering a site
click; other native actions are temporarily disabled, but the same address icon
remains available to close the bubble. Backgrounding or leaving vertical
layout cancels the bubble. No browser Back/Refresh controls are repeated in the
horizontal website toolbar because the regular browser chrome already owns them.
The webpage relies on native container safe areas. A KVO observation of
`WKWebView.underPageBackgroundColor` follows WebKit's resolved page color,
including CSS updates, without evaluating page JavaScript. Only that color
layer ignores container safe areas behind the native rail; the rail's base
background is transparent, while normal item glass is preserved.
Start/error pages use their own system background colors rather than an old
website's color. Neither the webpage nor its hit targets ignore safe areas.

The native toolbar contains trusted browser Back and Refresh/Stop plus the
website-declared navigation and special actions. Website-specific items require
an approved configuration; ordinary sites retain core browser controls without
an empty site-control pane. The existing WebKit
instance remains owned by the tab across toolbar installation, clearing, and
pose changes. Older iOS versions use an explicit control-sheet launcher.
Complex option controls become native menus in the slim strip; an All Website
Controls item opens the full labeled presentation with badges and options.
All display-adaptation APIs are public and availability-gated to iOS 27.1.
The implementation follows Apple's
[toolbar axis behavior](https://developer.apple.com/documentation/swiftui/toolbarcontent/axisbehavior(_:))
and [system-selected vertical edge](https://developer.apple.com/documentation/swiftui/environmentvalues/toolbarverticaledge).
The edge is read-only; the app does not force an edge by overriding system
environment values or guessing the physical fold state.
The toolbar's real menu button opens a native sheet; follow-up actions run
after dismissal to avoid presenting two sheets at once.

`DuoCapabilityPresentation` presents scanner permission and scanner UI from the
currently active presentation container: the main browser for the native toolbar, or
the compact control sheet. Only one host is enabled at a time. Closing compact
controls cancels pending capability work and activation tokens without erasing
the site's approved panel. Navigation, tab switching, and revocation retain the
existing document/origin checks.

Both website scanning and the separate browser Scan Into Field tool use
ScannerView and persisted scanner preferences. Camera presentation is a
resizable 45%-height/large sheet with an explicit initial detent and compact
adaptation disabled, so compact-height layouts do not discard the smaller
detent. Background interaction is disabled. The website
bridge still emits only its existing scanner outcome events.

ScannerInput installs a fixed focus tracker at main-document start in its own
isolated content world. Only an explicit browser scan captures a one-shot field
ticket; a successful camera result applies through structured arguments after
native tab/navigation/foreground checks. Original values remain in JavaScript,
not the native model. A selected eligible input/textarea is revalidated before
insertion and optional synthetic Enter/normal requestSubmit. ScannerInputView
uses the page-tool ownership lifecycle, suspends site capability presentation,
and bounds asynchronous capture/insertion without persisting barcode values.

WebKit delegates and observable state are main-actor isolated. KVO callbacks
capture the view model weakly and dispatch state synchronization to the main
actor. The delegate references the view model weakly. WebKit retains a proxy
message handler that references the bridge weakly. Closing a tab stops loading,
settles dialogs, dismisses scanner/permission UI, removes bridge scripts and
handlers, invalidates observations, and detaches delegates.

## Project map

| Folder | Responsibility |
| --- | --- |
| `DuoBrowser/App` | SwiftUI application entry |
| `DuoBrowser/Browser` | navigation, normalization, tabs, wrapper, interface |
| `DuoBrowser/Data` | atomic local library, settings, WebKit downloads |
| `DuoBrowser/Bridge` | DuoKit SDK, schema, rate limits, origins, permissions |
| `DuoBrowser/DuoControls` | declarative models and trusted native rendering |
| `DuoBrowser/Scanner` | permission-controlled VisionKit live scanning |
| `DuoBrowser/Views` | library, settings, permissions, website dialogs, sharing |
| `DuoBrowser/Resources/Demo` | offline DuoKit integration with HTML fallback |
| `DuoBrowserTests` | native unit tests |
| `DuoBrowserUITests` | native UI smoke test |
| `Tests` | dependency-free SDK tests and project-wiring validation |

## Browsing and isolation

The URL normalizer distinguishes addresses, searches, allowlisted external app
links, and rejected input. Search providers build encoded URL queries rather
than concatenating untrusted parameters. HTTP is permitted for general browsing
but never grants DuoKit access. Default certificate handling is not overridden.
File access through navigation is restricted to the exact bundled demo page.

Regular tabs share WebKit's default persistent data store. Private tabs share a
separate nonpersistent store for their private session, which is replaced after
the last private tab closes. Tabs never share WebKit instances, native panels,
document identifiers, activation tokens, JavaScript dialogs, or pending scan
requests. Normal site permissions are origin-scoped; private choices remain in
the requesting tab's memory and expire with it.

New-window navigation routes a `URLRequest` to a new tab in the same regular or
private session. Full popup `Window` proxy/opener semantics are not implemented.
The final closed tab is replaced with a fresh start tab rather than leaving an
empty application.

Recently closed regular pages are kept only in the manager's memory, bounded
by the configured maximum tab count. Private and start-page tabs are excluded.
Reopening creates a new web view with the saved URL, desktop preference, and
page zoom; it is not a serialized back/forward/form-state restore. A failed
reopen at the tab limit retains the entry. Confirmed close-all operates on
one browsing session and batches session persistence rather than writing once
per closed tab.

The tab overview uses a two-column lazy grid (one column at accessibility text
sizes), search by title/address, separate regular/private sessions, and native
new/close/select controls. Cards never instantiate web views. WebKit snapshots
are bounded to a short viewport crop at 240-point width, captured asynchronously,
and kept only in the visible card's memory. They are dropped on disappearance
or inactivity. Loading/start/error/unavailable states are clearly distinguished;
snapshot failures are logged without URLs or page content.

## Persistence

`BrowserLibrary` stores a version-one snapshot in Application Support using
atomic writes and iOS file protection. It contains settings, bookmarks/folder
labels, bounded deduplicated history, site decisions, regular tab URLs/content
preferences/selection, and nonprivate download metadata. Private history,
private tabs, private permissions, and private download records never enter
that snapshot. Explicit bookmarks and downloaded files are user-saved data,
including when created from private tabs.

`BrowserStartPageView` observes the shared library directly, so favorite changes
update the start page without rebuilding any web view. Its monograms do not
fetch remote favicons. Bookmark collections are filters over saved folder
labels, not nested filesystem folders. History is grouped by the user's
calendar start-of-day rather than fixed 24-hour intervals.

Reading List holds URL/title/date/read-state metadata only; it does not fetch
or cache article content. Explicit saved-page actions persist in regular or
private browsing, independently of private-history exclusions. Bookmark and
Reading List writes roll back their in-memory changes if persistence fails.
The bookmark editor stays open with an error on failure.

Optional favorites, Reading List, and per-tab zoom fields decode older
snapshots using their documented defaults. Wrong field types are not silently
discarded; unreadable storage remains protected from overwrite.

Session snapshots retain a requested HTTP/HTTPS address when WebKit has not yet
published one, so an early save cannot replace a restored URL with a blank.
Closed view models ignore late navigation callbacks and cannot be reactivated.
New-window tabs load the requested page directly without first opening the
configured startup website.

Read failures surface an error and protect the existing file from overwrite.
Write failures surface an error; they do not claim changes were persisted.
Retention and a 10,000-entry cap bound history.

Downloads use `WKDownload` and its `Progress`. A shared manager owns active
downloads independently of tab lifetime, sanitizes suggested filenames, prefixes
them with a UUID, and saves only inside Documents/Downloads. Filenames are
bounded to 180 UTF-8 bytes before adding the UUID; short extensions survive
truncation. Destinations are persisted before bytes arrive. Interrupted regular
downloads become failed records after restart and their saved partial files are
cleaned up. Cleanup errors retain the entry/path and surface an error.

Cancellation is asynchronous and shared between callers through a per-transfer
task. A cancelled row cannot be deleted until WebKit acknowledges cancellation;
late progress/failure/completion callbacks cannot turn it back into a completed
download. User-confirmed deletion removes the file before removing its record.
Saved paths must match the record's UUID and a single filename component; the
manager refuses recursive directory deletion. Sharing requires an actual regular
file, not a directory or symbolic link. Missing files produce a visible share
error but do not prevent removal of stale records.
Resume/background guarantees are not implemented.

Completed files can be opened in an embedded `QLPreviewController` after the
download manager validates their location and regular-file status. The native
preview data source provides exactly one file and its original display name.
Unsupported formats produce a visible error; native sharing remains available.

Clearing browsing data blocks tab mutations, tears down views, persists an empty
session before suspension, awaits all transfer cancellations, and only then
clears WebKit's persistent store. A fresh built-in start tab avoids immediately
repopulating cookies through a configured startup URL. Completed downloads and
bookmarks remain. The data-removal operation and download directory are injectable
in native tests so cleanup ordering and file operations can be verified without
touching production storage.

Page zoom uses `WKWebView.pageZoom`, not injected JavaScript or stylesheet
changes. Values are finite and restricted to 0.5–3.0, affect the existing web
view without a reload, and persist only with regular-tab session snapshots.
Clearing data also removes the in-memory recently closed list, while preserving
explicitly saved Reading List entries.

## DuoKit lifecycle

The browser injects `duo.js` at document start into the main frame's page world.
It calls WebKit's promise/reply handler using a versioned JSON envelope.
The bridge validates rate, size, schema, frame, origin, and permissions before
rendering. A bridge instance belongs to exactly one tab and web view.

Main navigation clears the panel, document identifier, pending permission,
scanner request, and activation token, even when the origin remains unchanged.
The next document must call `controls.set` again. Stored origin decisions may
reauthorize it; the previous configuration is never reused. Native event
delivery includes the SDK's per-document identifier, so a new document ignores
an event queued for its predecessor.

Only a native control action creates a single-use scanner gesture token, valid
for ten seconds. Scanner results require the same active origin, document,
generation, and tab that requested the scan. Backgrounding or switching tabs
stops scanning and prevents result delivery to another document.

## Platform limitations and validation

VisionKit scanning requires supported physical hardware, iOS camera permission,
and availability; simulators return an explicit unavailable error. WebKit
renders ordinary websites regardless of whether they integrate DuoKit.
Native platform behavior must be validated on simulator/device; Windows-side
JavaScript and project checks do not substitute for Xcode.
