const fs = require("node:fs");
const path = require("node:path");
const cp = require("node:child_process");

function safeSummary(raw) {
    const output = {};
    for (const key of ["passedTests", "failedTests", "skippedTests"]) {
        if (!Number.isSafeInteger(raw[key]) || raw[key] < 0) throw new Error("Unsupported test-result counts.");
        output[key] = raw[key];
    }
    return output;
}

module.exports = { safeSummary };
if (require.main === module) {
    const directory = "ci-summary";
    fs.mkdirSync(directory, { recursive: true });
    const bundle = "build/Tests.xcresult";
    try {
        let summary;
        if (!fs.existsSync(bundle)) {
            summary = { status: "unavailable", reason: "Native result bundle was not produced." };
        } else {
            const result = cp.execFileSync("xcrun", [
                "xcresulttool", "get", "test-results", "summary", "--path", bundle
            ], { encoding: "utf8", timeout: 20000, maxBuffer: 8 * 1024 * 1024, stdio: ["ignore", "pipe", "pipe"] });
            summary = safeSummary(JSON.parse(result));
        }
        fs.writeFileSync(path.join(directory, "test-counts.json"), JSON.stringify(summary, null, 2));
    } catch {
        console.error("Could not produce the sanitized test summary. No raw diagnostics were exported.");
        process.exitCode = 1;
    }
}
