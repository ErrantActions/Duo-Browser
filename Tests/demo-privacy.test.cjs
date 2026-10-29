const test = require("node:test");
const assert = require("node:assert/strict");
const vm = require("node:vm");
const fs = require("node:fs");
const path = require("node:path");

function createDemo(available = true) {
    const elements = new Map();
    const callbacks = [];
    const requests = [];
    const panels = [];
    const document = {
        querySelector(selector) {
            if (!elements.has(selector)) elements.set(selector, { textContent: "", style: {} });
            return elements.get(selector);
        }
    };
    const window = {
        duo: {
            isAvailable: true,
            version: "1.0",
            device: { capabilities: () => Promise.resolve({ controls: true }) },
            events: { subscribe: callback => callbacks.push(callback) },
            scanner: { request: request => { requests.push(request); return Promise.resolve({ ok: true }); } },
            controls: {
                set: panel => { panels.push(JSON.parse(JSON.stringify(panel))); return Promise.resolve({ ok: true }); },
                update: panel => { panels.push(JSON.parse(JSON.stringify(panel))); return Promise.resolve({ ok: true }); },
                clear: () => Promise.resolve({ ok: true })
            }
        }
    };
    if (!available) delete window.duo;
    const source = fs.readFileSync(path.join(__dirname, "..", "DuoBrowser", "Resources", "Demo", "demo.js"), "utf8");
    vm.runInNewContext(source, { window, document, console });
    return { elements, callbacks, requests, panels };
}

test("the demo hides gesture tokens in its visible log but still sends the real request token", async () => {
    const { elements, callbacks, requests } = createDemo();
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

test("native website navigation changes the record and updates bounded native controls", async () => {
    const { elements, callbacks, panels } = createDemo();
    elements.get("#install").onclick();
    assert.equal(panels[0].controls.length, 8);
    assert.equal(panels[0].controls.find(control => control.id === "previous").enabled, false);
    callbacks[0]({ type: "duo.controlActivated", controlId: "next", payload: {} });
    await new Promise(resolve => setImmediate(resolve));
    assert.equal(elements.get("#record-position").textContent, "Record 2 of 3");
    const next = panels.at(-1);
    assert.equal(next.controls.find(control => control.id === "previous").enabled, true);
    assert.equal(next.controls.find(control => control.id === "reserve").payload.part, "LP-200");
    callbacks[0]({ type: "duo.controlActivated", controlId: "previous", payload: {} });
    assert.equal(elements.get("#record-position").textContent, "Record 1 of 3");
    assert.equal(panels.at(-1).controls.find(control => control.id === "previous").enabled, false);
});

test("HTML navigation remains functional outside Duo Browser", () => {
    const { elements, panels } = createDemo(false);
    for (let index = 0; index < 5; index++) elements.get("#html-next").onclick();
    assert.equal(elements.get("#record-position").textContent, "Record 3 of 3");
    assert.equal(elements.get("#html-next").disabled, true);
    elements.get("#html-previous").onclick();
    assert.equal(elements.get("#record-position").textContent, "Record 2 of 3");
    assert.equal(panels.length, 0);
});

test("page background checks switch readable light and dark colors without native requests", () => {
    const { elements, panels, requests } = createDemo(false);
    elements.get("#background").onclick();
    assert.equal(elements.get("body").style.backgroundColor, "rgb(224, 245, 236)");
    assert.equal(elements.get("#background-status").textContent, "Page background: Teal");
    elements.get("#background").onclick();
    assert.equal(elements.get("body").style.backgroundColor, "rgb(20, 42, 61)");
    assert.equal(elements.get("body").style.color, "#f2f7ff");
    assert.equal(elements.get("#background-status").textContent, "Page background: Navy");
    assert.equal(panels.length, 0);
    assert.equal(requests.length, 0);
});
