# Duo Web API 1.0

**DuoKit** is the website SDK. **duo.js** is browser-injected; websites do not
need to load a script from a CDN. **window.duo** is the public JavaScript API.
**Duo Controls** configure a native **Duo Panel** in Duo Browser.

Only HTTPS main frames and the exact bundled demo can use native capabilities.
Feature-detect and retain ordinary HTML controls for other browsers:

```js
if (window.duo?.isAvailable) {
    console.log(window.duo.version); // "1.0"
    await window.duo.controls.set({
        id: "part-actions",
        title: "Part Actions",
        accent: "blue",
        controls: [{
            id: "scan",
            type: "button",
            label: "Scan LP",
            icon: "barcode.viewfinder"
        }, {
            id: "consume",
            type: "primary",
            label: "Consume",
            requiresConfirmation: true,
            payload: { part: "LP-100" }
        }]
    });
}
```

## Methods

All commands return promises. Catch rejections and present a useful HTML
fallback; permission denial, invalid input, navigation, inactive tabs, and rate
limits are not success responses.

| API | Result |
| --- | --- |
| `duo.controls.set(configuration)` | `{ok: true}` after validation/permission |
| `duo.controls.update(configuration)` | Full replacement with same active panel ID |
| `duo.controls.clear()` | `{ok: true}`, removes the website control pane/sheet |
| `duo.events.subscribe(callback)` | Synchronous unsubscribe function |
| `duo.device.capabilities()` | version, controls, scanner hardware support, gesture requirement, control limit |
| `duo.scanner.request({requestId, gestureToken})` | `{ok: true}` when scanner presentation is accepted; outcome arrives as an event |

`isAvailable` indicates an injected API, not an already-granted permission.
`capabilities().scanner` reports hardware support, not camera authorization or
current availability. API injection alone does not grant access on HTTP pages.

## Configuration schema

Objects reject unknown fields, wrong types, explicit null for optional
configuration fields, duplicate identifiers, and invalid combinations.
Optional fields should be omitted when unused.

Panel:

| Field | Type / bound |
| --- | --- |
| `id` | Required identifier |
| `title` | Optional nonempty text, 80 characters |
| `accent` | Optional: `blue`, `green`, `orange`, `purple`, `pink` |
| `controls` | Required array, 1–8 entries, at least one non-spacer |

Control:

| Field | Type / bound |
| --- | --- |
| `id` | Required identifier, unique in panel |
| `type` | `button`, `toggle`, `segmented`, `menu`, `primary`, `spacer` |
| `label` | Required nonempty text, maximum 80 characters |
| `icon` | Optional catalog entry below |
| `enabled` | Optional boolean, defaults true |
| `badge` | Optional nonempty text, maximum 12 characters |
| `accessibilityLabel` | Optional nonempty text, maximum 160 characters |
| `requiresConfirmation` | Optional boolean; native website-attributed confirmation |
| `payload` | Optional JSON object returned when activated |
| `value` | Toggle: boolean; segmented/menu: one of the option IDs |
| `options` | Segmented/menu only: 2–5 `{id, label}` objects, unique IDs, label ≤40 characters |

Identifiers are 1–64 ASCII letters, numbers, `_`, or `-`. Text cannot contain
control characters. Payloads allow finite JSON numbers, booleans, null,
strings (≤2048 characters), objects (≤32 keys), and arrays (≤32 elements),
with at most six nesting levels. Object keys are nonempty text of ≤80 characters.
All content, including the envelope, must fit in **32,768 UTF-8 bytes**.

The API processes at most **20 messages per sliding 10-second window per tab**.
Navigation does not reset that limiter. Calls rejected by it do not apply changes.

Example value controls:

```js
const controls = [
    { id: "urgent", type: "toggle", label: "Urgent", value: false },
    { id: "quantity", type: "segmented", label: "Quantity", value: "one",
      options: [{ id: "one", label: "One" }, { id: "two", label: "Two" }] },
    { id: "more", type: "menu", label: "More",
      options: [{ id: "details", label: "Details" }, { id: "refresh", label: "Refresh" }] }
];
```

`update` is not a patch. Send the complete configuration with the existing panel
ID. Native toggle/segment/menu selection updates native state and returns its
value in `event.payload.value`, overriding any payload field named `value`.

### Icon catalog

`barcode.viewfinder`, `qrcode`, `checkmark.circle`, `plus`, `minus`, `star`,
`heart`, `cart`, `magnifyingglass`, `arrow.clockwise`,
`person.crop.circle.badge.plus`, `square.and.arrow.up`, `list.bullet`, `play`,
`pause`, `stop`, `chevron.left`, `chevron.right`, `trash`.

These are trusted native symbol identifiers, not arbitrary image URLs.
Accent requests never override browser attribution, system appearance, or
permission UI. On iOS 27.1, site controls are real system toolbar items that
prefer native vertical presentation on iPhone Duo. There is no custom half-screen
split or fixed 700-point threshold; SwiftUI chooses presentation for the current
pose/locale. Back and Refresh/Stop remain trusted browser actions.
Segmented/menu options use native menus and toggles use native toggle buttons.
**All Website Controls** opens a full labeled, vertically scrollable sheet,
including badges. Older iOS versions use the **Duo Controls** sheet launcher.
Websites cannot configure the browser's address/navigation UI.
In vertical-toolbar contexts the URL is a trusted collapsed browser button,
not part of the website's configuration. The browser does not reserve a second
bottom address/toolbar area. Opening its address editor temporarily suspends
website capability prompts; it does not transfer a site's authorization.

## Events

```js
const unsubscribe = window.duo.events.subscribe(async event => {
    if (event.type === "duo.controlActivated") {
        console.log(event.controlId, event.payload);
    }
});
// unsubscribe() when your integration is disposed.
```

Example event:

```json
{
  "type": "duo.controlActivated",
  "panelId": "part-actions",
  "controlId": "scan",
  "timestamp": "2026-10-27T20:00:00Z",
  "payload": {},
  "gestureToken": "UUID generated by Duo Browser"
}
```

Unneeded optional event fields are omitted. Only the requesting tab/document
receives native events. The SDK's internal `duo.native` DOM event is a delivery
mechanism, not a permission or trusted website identity signal; site scripts can
forge their own DOM events. Native capabilities always revalidate authorization.

## Scanner

Scanning is not a control action type and cannot be invoked just by installing
a configuration. Respond to a fresh native control activation:

```js
window.duo.events.subscribe(async event => {
    if (event.type === "duo.controlActivated" && event.controlId === "scan") {
        try {
            await window.duo.scanner.request({
                requestId: "scan_1",
                gestureToken: event.gestureToken
            });
        } catch (error) {
            console.error("Scanning unavailable or denied", error);
        }
    }
    if (event.type === "duo.scannerResult") {
        // event.requestId, event.value, event.format
    }
});
```

Tokens expire after ten seconds and are consumed once. A site may wait for its
scanner permission prompt after submitting a valid fresh token. Camera access
still requires the ordinary iOS camera permission. A request never launches a
scanner in a background/inactive tab. Scanning is limited to 60 seconds with a
visible live preview and Cancel button; the first result ends the scan and
suppresses duplicates.

Supported Vision barcode symbologies: QR, EAN-13, EAN-8, Code 128, Code 39,
PDF417, Aztec, Data Matrix, UPC-E. `format` is Vision's symbology raw string.

Outcomes:

- `duo.scannerResult`: `requestId`, `value`, `format`.
- `duo.scannerCancelled`: `requestId`.
- `duo.scannerError`: `requestId`, user-facing `error`.

Scanned values are not interpreted as URLs, opened automatically, stored by Duo,
or sent to a service. They are delivered only to the same authorized active
document and tab. A site receiving a result controls its own subsequent data
handling; disclose that behavior to your users.

## Lifecycle and permissions

Browser-owned automatic Site Navigation may provide same-site link shortcuts on
ordinary pages. It is not a DuoKit configuration or capability grant.
An approved `controls.set` panel suppresses those detected links immediately;
`controls.clear` can reveal the browser fallback again when detection is
enabled. The two sets are never merged. Sites should keep their own HTML menu:
Duo does not remove it, and ambiguous/script-only navigation may not be detected.

### Scanner presentation and browser keyboard input

The native scanner now defaults to a compact, resizable sheet instead of taking
over the entire screen. Users choose compact/expanded presentation, recognition
types, and vibration in Scanner Settings. These preferences can restrict which
codes a DuoKit scan recognizes; `capabilities().scanner` continues to mean hardware
support, not a guarantee of camera authorization or any particular code.

**Browser Menu → Scan Into Field** is a separate, user-initiated browser tool.
Its insertion and Enter/form-submit preferences do not change
`duo.scanner.request` or `duo.scannerResult`. DuoKit sites remain responsible for
putting a received result into their own UI and deciding whether to submit.
Do not process a result both as a site event and as keyboard-wedge input.
The bundled demo fills its Barcode field from a DuoKit result but deliberately
does not submit it. Its local lookup form also demonstrates the browser tool.

### Document ownership

The user must approve native panels for an exact HTTPS origin (scheme, host,
port). Different ports/subdomains do not inherit approval. The built-in demo
has a dedicated `duo-demo` identity. Stored decisions can authorize subsequent
documents, but every main navigation clears the old panel and requires `set`
again. Iframes cannot request capabilities. Same-document fragment changes do
not install a new SDK.

Private choices live only in the requesting tab's memory. Users can revoke site
access through **Browser menu → Duo Site Permissions**. Native panel rendering
always identifies the website and provides a **Hide Duo Controls** escape
action. The browser menu can restore the panel without navigation. The same
configuration/event API works in both layouts; sites do not supply frame sizes
or request access to a physical display.

## Transport envelope

Website integrations should use the public API rather than this internal
transport. Every message has `version: "1.0"`, `documentId` (a UUID generated
for that document by the SDK), and `method`. Only `controls.set/update` may add
`configuration`; only `scanner.request` may add `requestId` and `gestureToken`.
`controls.clear` and `device.capabilities` have no other fields. Unknown methods
and fields are rejected, with a rejected JavaScript promise.

See [security model](SECURITY.md) for native extension requirements.
