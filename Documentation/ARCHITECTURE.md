# Duo Browser architecture

## Ownership and UI

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

The native toolbar contains trusted browser Back and Refresh/Stop plus the
website-declared navigation and special actions. It appears only for an approved
configuration; ordinary sites have no empty side pane. The existing WebKit
instance remains owned by the tab across toolbar installation, clearing, and
pose changes. Older iOS versions use an explicit control-sheet launcher.
Complex option controls become native menus in the slim strip; an All Website
Controls item opens the full labeled presentation with badges and options.
All display-adaptation APIs are public and availability-gated to iOS 27.1.
The toolbar's real menu button opens a native sheet; follow-up actions run
after dismissal to avoid presenting two sheets at once.

`DuoCapabilityPresentation` presents scanner permission and scanner UI from the
currently active presentation container: the main browser for the native toolbar, or
the compact control sheet. Only one host is enabled at a time. Closing compact
controls cancels pending capability work and activation tokens without erasing
the site's approved panel. Navigation, tab switching, and revocation retain the
existing document/origin checks.

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
