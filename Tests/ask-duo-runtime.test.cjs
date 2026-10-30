const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

test("assistant UI fixtures are explicit debug-only dependencies, never release fallbacks", () => {
    const root = path.join(__dirname, "..");
    const model = fs.readFileSync(path.join(root, "DuoBrowser", "Browser", "AskDuoModel.swift"), "utf8");
    const release = model.replace(/^\s*#if DEBUG[\s\S]*?^\s*#endif/gm, "");
    assert.doesNotMatch(release, /UI TEST RESPONSE|--ask-duo-ui-fixture/);
    assert.match(release, /return AskDuoModel\(\)/);
    assert.match(release, /LanguageModelSession\(model: SystemLanguageModel\.default\)/);
    assert.match(release, /guard !model\.isPrivate, !model\.isClosed/);
    const view = fs.readFileSync(path.join(root, "DuoBrowser", "Browser", "AskDuoView.swift"), "utf8");
    assert.match(view, /UI TEST ENGINE/);
    assert.match(view, /prepareSend\(includingPage: true\)/);
    const tests = fs.readFileSync(path.join(root, "DuoBrowserTests", "AskDuoTests.swift"), "utf8");
    assert.match(tests, /testRealAppleModelWhenRuntimeIsUsable/);
    assert.match(tests, /Reply with OK only\./);
    assert.match(tests, /Live inference remains unverified/);
});

test("normal assistant presentation is off across both toolbars and the sheet presenter", () => {
    const root = path.join(__dirname, "..", "DuoBrowser");
    const model = fs.readFileSync(path.join(root, "Browser", "AskDuoModel.swift"), "utf8");
    assert.match(model, /static let isEnabled = false/);
    assert.match(model, /static var isVisible: Bool \{ isEnabled \|\| usesUITestFixture \}/);
    for (const file of [path.join(root, "Browser", "BrowserToolbar.swift"), path.join(root, "DuoControls", "DuoNativeToolbar.swift")]) {
        assert.match(fs.readFileSync(file, "utf8"), /if AskDuoModel\.isVisible \{[\s\S]*?present\(\.assistant\)/);
    }
    const presenter = fs.readFileSync(path.join(root, "Browser", "BrowserView.swift"), "utf8");
    assert.match(presenter, /if selection == \.assistant, !AskDuoModel\.isVisible/);
    assert.match(presenter, /Ask Duo is temporarily unavailable\./);
});
