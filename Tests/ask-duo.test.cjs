const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const script = fs.readFileSync(path.join(__dirname, "..", "DuoBrowser", "Resources", "AskDuoContext.js"), "utf8");
const documentID = "00000000-0000-4000-8000-000000000001";

class Element {
    constructor(tag, parent = null, attributes = {}) {
        this.tagName = tag.toUpperCase();
        this.parentElement = parent;
        this.attributes = attributes;
        this.nodes = [];
        this.style = { display: "block", visibility: "visible", opacity: "1" };
        if (parent) parent.nodes.push(this);
    }
    hasAttribute(name) { return Object.hasOwn(this.attributes, name); }
    getAttribute(name) { return this.attributes[name] ?? null; }
    getClientRects() { return this.style.display === "none" ? [] : [{}]; }
    getElementsByTagName(tag) {
        return this.nodes.flatMap(node => node instanceof Element
            ? [...(node.tagName === tag.toUpperCase() ? [node] : []), ...node.getElementsByTagName(tag)]
            : []);
    }
    querySelectorAll(selector) {
        const tags = selector.split(",").map(value => value.toUpperCase());
        return this.nodes.flatMap(node => node instanceof Element
            ? [...(tags.includes(node.tagName) ? [node] : []), ...node.querySelectorAll(selector)]
            : []);
    }
    querySelector(selector) { return this.querySelectorAll(selector)[0] ?? null; }
    closest() {
        for (let node = this; node; node = node.parentElement) {
            if (["FORM", "INPUT", "TEXTAREA", "SELECT", "OPTION", "BUTTON", "SCRIPT", "STYLE", "NOSCRIPT", "IFRAME"].includes(node.tagName)
                || ["contenteditable", "hidden", "inert"].some(name => node.hasAttribute(name))
                || ["form", "textbox", "searchbox", "combobox", "spinbutton"].includes(node.getAttribute("role"))
                || node.getAttribute("aria-hidden") === "true") return node;
        }
        return null;
    }
}
function text(parent, value) { parent.nodes.push({ parentElement: parent, textContent: value }); }
function environment() {
    const body = new Element("body");
    const links = [];
    const document = {
        body, links, title: "Context fixture", querySelector: () => null,
        createTreeWalker(root) {
            const nodes = [];
            function visit(node) {
                for (const child of node.nodes) {
                    if (child instanceof Element) visit(child);
                    else nodes.push(child);
                }
            }
            visit(root);
            let index = 0;
            return { nextNode: () => nodes[index++] ?? null };
        }
    };
    const context = vm.createContext({
        document, URL, NodeFilter: { SHOW_TEXT: 4 },
        location: { href: "https://example.test/article" },
        crypto: { randomUUID: () => documentID },
        getComputedStyle: element => element.style,
        mode: "capture"
    });
    function link(href, label, parent = body, attributes = {}) {
        const anchor = new Element("a", parent, attributes);
        anchor.href = href;
        text(anchor, label);
        links.push(anchor);
        return anchor;
    }
    return { body, context, link, run: () => vm.runInContext(`(function () { ${script} })()`, context) };
}

test("Ask Duo excludes form, editable, hidden, frame and script text without reading input values", () => {
    const page = environment();
    text(page.body, "Visible article.");
    for (const tag of ["form", "input", "textarea", "select", "iframe", "script", "button"]) {
        const node = new Element(tag, page.body);
        text(node, "PRIVATE_FIELD_MARKER");
        Object.defineProperty(node, "value", { get() { throw new Error("Input value must never be read"); } });
    }
    text(new Element("div", page.body, { contenteditable: "true" }), "PRIVATE_FIELD_MARKER");
    for (const role of ["form", "textbox", "searchbox", "combobox", "spinbutton"]) {
        text(new Element("div", page.body, { role }), "PRIVATE_FIELD_MARKER");
    }
    const hidden = new Element("div", page.body);
    hidden.style.display = "none";
    text(hidden, "HIDDEN_MARKER");
    const result = JSON.parse(page.run());
    assert.equal(result.text, "Visible article.");
    assert.equal(result.documentID, documentID);
    assert.ok(!result.text.includes("PRIVATE_FIELD_MARKER"));
    assert.ok(!result.text.includes("HIDDEN_MARKER"));
});

test("Ask Duo bounds excerpts and links and excludes non-HTTPS, credentials, downloads and action buttons", () => {
    const page = environment();
    text(page.body, "Article ".repeat(1000));
    page.link("http://example.test/", "HTTP");
    page.link("javascript:alert(1)", "Script");
    page.link("https://user:pass@example.test/", "Credentials");
    page.link("https://example.test/download", "File", page.body, { download: "" });
    page.link("https://example.test/action", "Action", page.body, { role: "button" });
    for (let index = 0; index < 20; index++) page.link(`https://example.test/${index}`, "Readable ".repeat(20));
    const result = JSON.parse(page.run());
    assert.equal(result.text.length, 1800);
    assert.equal(result.truncated, true);
    assert.equal(result.links.length, 12);
    assert.ok(result.links.every(link => link.href.startsWith("https://example.test/") && link.label.length <= 60));
});

test("Ask Duo prioritizes article text and links over site-wide navigation", () => {
    const page = environment();
    text(page.body, "Site navigation");
    page.link("https://example.test/menu", "Menu");
    const main = new Element("main", page.body);
    text(main, "The article content.");
    page.link("https://example.test/article-next", "Article next", main);
    page.context.document.querySelector = () => main;
    const result = JSON.parse(page.run());
    assert.ok(result.text.startsWith("The article content."));
    assert.ok(!result.text.includes("Site navigation"));
    assert.equal(result.links[0].href, "https://example.test/article-next");
});

test("Ask Duo validates the original isolated document, source address and still-visible captured link", () => {
    const page = environment();
    text(page.body, "Article");
    const anchor = page.link("https://example.test/next", "Next page");
    page.run();
    Object.assign(page.context, {
        mode: "validate", sourceURL: "https://example.test/article",
        documentID, href: anchor.href
    });

    assert.equal(page.run(), true);
    page.context.documentID = "different-document";
    assert.equal(page.run(), false);
    page.context.documentID = documentID;
    page.context.location.href = "https://example.test/other";
    assert.equal(page.run(), false);
    page.context.location.href = page.context.sourceURL;
    anchor.style.display = "none";
    assert.equal(page.run(), false);
});

test("Reading View uses structured local blocks and still excludes forms and hidden/editable content", () => {
    const page = environment();
    page.context.mode = "reader";
    text(new Element("h1", page.body), "Article heading");
    text(new Element("p", page.body), "Readable paragraph.");
    text(new Element("li", page.body), "A list item");
    text(new Element("blockquote", page.body), "A quotation");
    const form = new Element("form", page.body);
    text(new Element("p", form), "PRIVATE_FIELD_MARKER");
    text(new Element("p", page.body, { contenteditable: "true" }), "PRIVATE_FIELD_MARKER");
    const hidden = new Element("p", page.body);
    hidden.style.visibility = "hidden";
    text(hidden, "HIDDEN_MARKER");
    const result = JSON.parse(page.run());
    assert.deepEqual(result.blocks.map(block => block.kind), ["heading", "body", "list", "quote"]);
    assert.ok(!JSON.stringify(result.blocks).includes("PRIVATE_FIELD_MARKER"));
    assert.ok(!JSON.stringify(result.blocks).includes("HIDDEN_MARKER"));
});

test("Reading View bounds long articles rather than returning an unbounded page", () => {
    const page = environment();
    page.context.mode = "reader";
    for (let index = 0; index < 900; index++) text(new Element("p", page.body), "Article ".repeat(100));
    const result = JSON.parse(page.run());
    assert.ok(result.blocks.length <= 400);
    assert.ok(result.blocks.reduce((sum, block) => sum + block.text.length, 0) <= 30000);
    assert.equal(result.truncated, true);
});
