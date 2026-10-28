const test = require("node:test");
const assert = require("node:assert/strict");
const vm = require("node:vm");
const fs = require("node:fs");
const path = require("node:path");

test("the demo hides gesture tokens in its visible log but still sends the real request token", async () => {
    const elements = new Map();
    const callbacks = [];
    const requests = [];
    const document = {
        querySelector(selector) {
            if (!elements.has(selector)) elements.set(selector, { textContent: "" });
            return elements.get(selector);
        }
    };
    const window = {
        duo: {
            isAvailable: true,
            version: "1.0",
            device: { capabilities: () => Promise.resolve({ controls: true }) },
            events: { subscribe: callback => callbacks.push(callback) },
            scanner: { request: request => { requests.push(request); return Promise.resolve({ ok: true }); } }
        }
    };
    const source = fs.readFileSync(path.join(__dirname, "..", "DuoBrowser", "Resources", "Demo", "demo.js"), "utf8");
    vm.runInNewContext(source, { window, document, console });
    const token = "test-token";
    callbacks[0]({
        type: "duo.controlActivated", controlId: "scan", gestureToken: token, payload: {}
    });
    await new Promise(resolve => setImmediate(resolve));
    const output = elements.get("#log").textContent;
    assert.ok(output.includes("duo.controlActivated"));
    assert.ok(output.includes("[redacted]"));
    assert.ok(!output.includes(token));
    assert.equal(requests[0].gestureToken, token);
});
