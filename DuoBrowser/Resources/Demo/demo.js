"use strict";
const logElement = document.querySelector("#log");
function log(value) {
    const displayValue = value && typeof value === "object" && Object.hasOwn(value, "gestureToken")
        ? { ...value, gestureToken: "[redacted]" }
        : value;
    const text = typeof displayValue === "string" ? displayValue : JSON.stringify(displayValue, null, 2);
    logElement.textContent = `${new Date().toLocaleTimeString()} ${text}\n${logElement.textContent}`.slice(0, 16000);
}
const panel = {
    id: "part-actions",
    title: "Part Actions",
    accent: "blue",
    controls: [
        { id: "previous", type: "button", label: "Previous Record", icon: "chevron.left", enabled: false },
        { id: "next", type: "button", label: "Next Record", icon: "chevron.right" },
        { id: "scan", type: "button", label: "Scan", icon: "barcode.viewfinder" },
        { id: "reserve", type: "button", label: "Reserve", icon: "person.crop.circle.badge.plus", payload: { part: "LP-100" } },
        { id: "urgent", type: "toggle", label: "Urgent", value: false },
        { id: "quantity", type: "segmented", label: "Quantity", value: "one", options: [
            { id: "one", label: "One" }, { id: "two", label: "Two" }, { id: "three", label: "Three" }
        ] },
        { id: "actions", type: "menu", label: "More", options: [
            { id: "details", label: "Details" }, { id: "refresh", label: "Refresh" }
        ] },
        { id: "consume", type: "primary", label: "Consume", icon: "checkmark.circle", requiresConfirmation: true }
    ]
};
const records = ["LP-100: Sample Part", "LP-200: Second Part", "LP-300: Final Part"];
let recordIndex = 0;
function moveRecord(offset) {
    recordIndex = Math.max(0, Math.min(records.length - 1, recordIndex + offset));
    document.querySelector("#record-position").textContent = `Record ${recordIndex + 1} of ${records.length}`;
    document.querySelector("#record-title").textContent = records[recordIndex];
    document.querySelector("#html-previous").disabled = recordIndex === 0;
    document.querySelector("#html-next").disabled = recordIndex === records.length - 1;
    panel.controls.find(control => control.id === "previous").enabled = recordIndex > 0;
    panel.controls.find(control => control.id === "next").enabled = recordIndex < records.length - 1;
    panel.controls.find(control => control.id === "reserve").payload = { part: records[recordIndex].split(":")[0] };
}
const available = Boolean(window.duo?.isAvailable);
document.querySelector("#availability").textContent = available
    ? `DuoKit ${window.duo.version} is available. Install a panel to request site permission.`
    : "DuoKit is unavailable. Use the HTML fallback controls below.";
async function perform(action) {
    try { log(await action()); }
    catch (error) { log(`Request rejected: ${error.message || error}`); }
}
document.querySelector("#install").onclick = () => {
    if (!available) return log("Outside Duo Browser: HTML fallback remains available.");
    perform(() => window.duo.controls.set(panel));
};
document.querySelector("#update").onclick = () => {
    panel.title = "Updated Part Actions";
    panel.controls.find(control => control.id === "reserve").badge = "1";
    if (available) perform(() => window.duo.controls.update(panel));
    else log("HTML controls updated: reserved count 1.");
};
document.querySelector("#clear").onclick = () => {
    if (available) perform(() => window.duo.controls.clear());
    else log("No native panel to clear.");
};
if (available) {
    perform(() => window.duo.device.capabilities());
    window.duo.events.subscribe(event => {
        log(event);
        if (event.type !== "duo.controlActivated") return;
        const control = panel.controls.find(item => item.id === event.controlId);
        if (control && event.payload.value !== undefined) control.value = event.payload.value;
        if (event.controlId === "previous" || event.controlId === "next") {
            moveRecord(event.controlId === "next" ? 1 : -1);
            perform(() => window.duo.controls.update(panel));
        }
        if (event.controlId === "scan") {
            perform(() => window.duo.scanner.request({
                requestId: `scan_${Date.now()}`, gestureToken: event.gestureToken
            }));
        }
    });
}
document.querySelector("#html-previous").onclick = () => moveRecord(-1);
document.querySelector("#html-next").onclick = () => moveRecord(1);
document.querySelector("#html-reserve").onclick = () => log("HTML action: Reserve");
document.querySelector("#html-toggle").onchange = event => log({ urgent: event.target.checked });
document.querySelector("#html-quantity").onchange = event => log({ quantity: event.target.value });
document.querySelector("#alert").onclick = () => alert("Hello from the DuoKit demo website.");
document.querySelector("#confirm").onclick = () => log({ confirmed: confirm("Confirm this demo website action?") });
document.querySelector("#prompt").onclick = () => log({ response: prompt("Enter a demo response", "Hello") });
document.querySelector("#clear-log").onclick = () => { logElement.textContent = ""; };
