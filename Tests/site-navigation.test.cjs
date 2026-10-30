const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const script = fs.readFileSync(path.join(__dirname, "..", "DuoBrowser", "Resources", "SiteNavigation.js"), "utf8");
const documentID = "00000000-0000-4000-8000-000000000001";

class Element {
    constructor(tag, parent, attributes = {}, text = "") {
        this.tagName = tag.toUpperCase();
        this.parentElement = parent;
        this.attributes = attributes;
        this.innerText = text;
        this.nodes = [];
        this.style = { display: "block", visibility: "visible", opacity: "1" };
        if (parent) parent.nodes.push(this);
    }
    getAttribute(name) { return this.attributes[name] ?? null; }
    hasAttribute(name) { return Object.hasOwn(this.attributes, name); }
    getClientRects() { return this.style.display === "none" ? [] : [{}]; }
    matches(selector) {
        return selector.split(",").some(part => {
            const attr = /^\[([^=\]]+)(?:=['"]?([^'"\]]+)['"]?)?\]$/.exec(part);
            return attr ? this.hasAttribute(attr[1]) && (attr[2] === undefined || this.getAttribute(attr[1]) === attr[2])
                : this.tagName === part.toUpperCase();
        });
    }
    closest(selector) {
        for (let node = this; node; node = node.parentElement) if (node.matches(selector)) return node;
        return null;
    }
    descendants() { return this.nodes.flatMap(node => [node, ...node.descendants()]); }
    querySelector(selector) { return this.descendants().find(node => node.matches(selector)) ?? null; }
}
function environment(address = "https://example.test/home") {
    const body = new Element("body", null);
    const messages = [], observers = [], timers = new Map();
    let timerID = 0;
    const document = {
        body, documentElement: body, baseURI: address, querySelector: () => null,
        createTreeWalker(root) {
            const nodes = root.descendants();
            let index = 0;
            return { nextNode: () => nodes[index++] ?? null };
        }
    };
    const context = vm.createContext({
        document, URL, NodeFilter: { SHOW_ELEMENT: 1 }, crypto: { randomUUID: () => documentID },
        getComputedStyle: node => node.style, location: { href: address }, mode: "capture", allowDemo: false,
        addEventListener() {}, performance: { now: () => 5000 },
        MutationObserver: class {
            constructor(callback) { this.callback = callback; observers.push(this); }
            observe() { this.connected = true; }
            disconnect() { this.connected = false; }
        },
        setTimeout(callback) { const id = ++timerID; timers.set(id, callback); return id; },
        clearTimeout(id) { timers.delete(id); },
        webkit: { messageHandlers: { siteNavigation: { postMessage: value => messages.push(value) } } }
    });
    function link(parent, href, label, attributes = {}) {
        return new Element("a", parent, { href, ...attributes }, label);
    }
    function run(mode = "capture", args = {}) {
        Object.assign(context, { mode, ...args });
        return vm.runInContext(script, context);
    }
    return { body, context, link, run, messages, observers, timers, capture: () => JSON.parse(run()) };
}
function primary(page) {
    const header = new Element("header", page.body);
    return new Element("nav", header, { "aria-label": "Primary navigation" });
}

test("site navigation prefers a visible primary landmark and never reads input values", () => {
    const page = environment(), nav = primary(page);
    page.link(nav, "/products", "Products");
    page.link(nav, "/help", "Help");
    const footer = new Element("footer", page.body);
    page.link(new Element("nav", footer), "/footer", "Footer");
    const input = new Element("input", nav);
    Object.defineProperty(input, "value", { get() { throw new Error("Must not read fields"); } });
    assert.deepEqual(page.capture().links.map(item => item.label), ["Products", "Help"]);
});

test("detected navigation excludes actions, foreign origins, credentials, scripts, editors and hidden links", () => {
    const page = environment(), nav = primary(page);
    page.link(nav, "/home", "Home");
    page.link(nav, "/help", "Help");
    for (const [href, label, attributes] of [
        ["https://other.test/", "Foreign", {}], ["javascript:alert(1)", "Script", {}],
        ["https://user:pass@example.test/", "Credentials", {}],
        ["/logout", "Sign Out", {}], ["/items?token=private", "Token", {}],
        ["/items?action=delete", "Action", {}], ["/download", "Download", { download: "" }],
        ["/new", "New Tab", { target: "_blank" }], ["/button", "Button", { role: "button" }],
        ["/bad/%zz", "Malformed", {}]
    ]) page.link(nav, href, label, attributes);
    const hidden = page.link(nav, "/hidden", "Hidden"); hidden.style.display = "none";
    new Element("input", page.link(nav, "/editor", "Editor"));
    assert.deepEqual(page.capture().links.map(item => item.label), ["Home", "Help"]);
});

test("site navigation deduplicates and bounds links and refuses ambiguous equal landmarks", () => {
    const page = environment(), nav = primary(page);
    for (let index = 0; index < 30; index++) page.link(nav, "/item/" + index, "Item " + index);
    page.link(nav, "/item/0", "Duplicate");
    assert.equal(page.capture().links.length, 12);
    const other = new Element("nav", new Element("header", page.body), { "aria-label": "Primary navigation" });
    page.link(other, "/different", "Other");
    page.link(other, "/another", "Another");
    assert.deepEqual(page.capture().links, []);
});

test("secondary/article menus and single links do not become main navigation", () => {
    const page = environment();
    const main = new Element("main", page.body);
    const nav = new Element("nav", main, { "aria-label": "Primary" });
    page.link(nav, "/one", "One"); page.link(nav, "/two", "Two");
    const breadcrumbs = new Element("nav", page.body, { "aria-label": "Breadcrumbs" });
    page.link(breadcrumbs, "/a", "A"); page.link(breadcrumbs, "/b", "B");
    page.link(new Element("nav", page.body), "/single", "Single");
    assert.deepEqual(page.capture().links, []);
});

test("detected-link activation rechecks document, source URL and continued primary membership", () => {
    const page = environment(), nav = primary(page);
    page.link(nav, "/products", "Products"); page.link(nav, "/help", "Help");
    const args = { sourceURL: page.context.location.href, documentID, href: "https://example.test/products" };
    assert.equal(page.run("validate", args), true);
    assert.equal(page.run("validate", { ...args, documentID: "different" }), false);
    nav.nodes.shift();
    assert.equal(page.run("validate", args), false);
});

test("navigation observation coalesces changes and posts only document identity, then disconnects", () => {
    const page = environment();
    page.run("watch");
    page.observers[0].callback(); page.observers[0].callback();
    assert.equal(page.timers.size, 1);
    page.timers.values().next().value();
    assert.deepEqual(Object.keys(page.messages[0]).sort(), ["documentID", "url"]);
    assert.equal(page.messages[0].documentID, documentID);
    page.run("pause");
    assert.equal(page.observers[0].connected, false);
});

test("the bundled demo supports only its own document fragments", () => {
    const page = environment("file:///bundle/Demo/index.html"), nav = primary(page);
    page.context.allowDemo = true;
    page.link(nav, "#catalog", "Catalog"); page.link(nav, "#help", "Help");
    page.link(nav, "other.html", "Other file");
    assert.deepEqual(page.capture().links.map(item => item.label), ["Catalog", "Help"]);
});
