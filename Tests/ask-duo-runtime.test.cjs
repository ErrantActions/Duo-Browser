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
