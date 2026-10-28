const test = require("node:test");
const assert = require("node:assert/strict");
const vm = require("node:vm");
const fs = require("node:fs");
const path = require("node:path");
const { randomUUID } = require("node:crypto");
const source = fs.readFileSync(path.join(__dirname, "..", "DuoBrowser", "Bridge", "duo.js"), "utf8");

function environment() {
    const messages = [];
    const listeners = {};
    const window = {
        webkit: { messageHandlers: { duo: {
            postMessage(message) { messages.push(message); return Promise.resolve({ ok: true }); }
        } } },
        addEventListener(name, callback) { listeners[name] = callback; }
    };
    const context = vm.createContext({ window, crypto: { randomUUID }, console });
    vm.runInContext(source, context);
    return { window, messages, listeners, context };
}

test("SDK exposes frozen versioned API and promise-backed commands", async () => {
    const { window, messages } = environment();
    assert.equal(window.duo.version, "1.0");
    assert.equal(window.duo.isAvailable, true);
    assert.ok(Object.isFrozen(window.duo));
    await window.duo.controls.set({ id: "test", controls: [] });
    await window.duo.controls.clear();
    assert.equal(messages[0].method, "controls.set");
    assert.equal(messages[0].version, "1.0");
    assert.equal(messages[0].documentId, messages[1].documentId);
    assert.equal(messages[1].method, "controls.clear");
});

test("events are scoped to a document and unsubscribe works", async () => {
    const { window, messages, listeners } = environment();
    await window.duo.device.capabilities();
    const events = [];
    const unsubscribe = window.duo.events.subscribe(event => events.push(event));
    listeners["duo.native"]({ detail: { documentId: "another-document", event: { type: "wrong" } } });
    assert.equal(events.length, 0);
    listeners["duo.native"]({ detail: { documentId: messages[0].documentId, event: { type: "duo.controlActivated" } } });
    assert.equal(events.length, 1);
    assert.ok(Object.isFrozen(events[0]));
    unsubscribe();
    listeners["duo.native"]({ detail: { documentId: messages[0].documentId, event: { type: "ignored" } } });
    assert.equal(events.length, 1);
});

test("scanner request carries only explicit request and gesture identifiers", async () => {
    const { window, messages } = environment();
    await window.duo.scanner.request({ requestId: "scan_1", gestureToken: "native-token", selector: "forbidden" });
    assert.equal(messages[0].method, "scanner.request");
    assert.equal(messages[0].requestId, "scan_1");
    assert.equal(messages[0].gestureToken, "native-token");
    assert.equal(messages[0].selector, undefined);
});

test("SDK is idempotent and does not appear outside Duo Browser", () => {
    const { window, context } = environment();
    const api = window.duo;
    vm.runInContext(source, context);
    assert.equal(window.duo, api);
    const standalone = { addEventListener() {} };
    vm.runInNewContext(source, { window: standalone });
    assert.equal(standalone.duo, undefined);
});
