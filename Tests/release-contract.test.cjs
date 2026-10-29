const test = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const cp = require("node:child_process");
const {
    parseBuildNumber, selectBuildNumber, permitted, validateProfile, makeToken,
    storeBuildNumber, entitlementPath, certificateMetadata
} = require("../.github/scripts/release-contract.cjs");
const { chooseDevice } = require("../.github/scripts/simulator.cjs");
const { safeSummary } = require("../.github/scripts/test-summary.cjs");

const teamId = "QM3794NUZS";
const bundleId = "com.errantactions.duobrowser";
const certificateDER = Buffer.from("test-certificate");
function profile() {
    return {
        TeamIdentifier: [teamId], Name: "Duo Browser App Store",
        UUID: "00000000-0000-4000-8000-000000000001",
        ExpirationDate: "2030-01-01T00:00:00Z",
        DeveloperCertificates: [certificateDER.toString("base64")],
        Entitlements: {
            "application-identifier": `${teamId}.${bundleId}`,
            "get-task-allow": false,
            "keychain-access-groups": [`${teamId}.*`]
        }
    };
}
const signing = { teamId, bundleId, certificateDER, now: Date.parse("2026-10-28T00:00:00Z") };

test("signed archives must preserve the owner's Boolean exempt-encryption declaration", () => {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), "duo-archive-contract-"));
    try {
        const source = path.join(directory, "info.json");
        for (const value of [false, true, undefined, "false"]) {
            fs.writeFileSync(source, JSON.stringify({
                CFBundleIdentifier: bundleId, CFBundleVersion: "1.0.4",
                ITSAppUsesNonExemptEncryption: value
            }));
            const result = cp.spawnSync(process.execPath, [
                path.join(__dirname, "..", ".github", "scripts", "release-contract.cjs"),
                "check-archive", source
            ], { encoding: "utf8", env: { ...process.env, APP_BUNDLE_ID: bundleId, BUILD_NUMBER: "1.0.4" } });
            assert.ifError(result.error);
            if (value === false) assert.equal(result.status, 0, result.stderr);
            else {
                assert.notEqual(result.status, 0);
                assert.match(result.stderr, /exempt-encryption declaration/);
            }
        }
    } finally { fs.rmSync(directory, { recursive: true }); }
});

test("build selection exceeds every prior upload, including dotted versions and migration counters", () => {
    assert.equal(selectBuildNumber([]), "1");
    assert.equal(selectBuildNumber(["1", "1000", "999"]), "1000.0.1");
    assert.equal(selectBuildNumber(["10.2.99", "2"]), "10.3");
    assert.equal(selectBuildNumber(["10.99.99"]), "11");
    assert.equal(selectBuildNumber(["10.2"], "12"), "12");
    assert.throws(() => selectBuildNumber(["10"], "9"));
    assert.throws(() => selectBuildNumber(["10"], "10.0.0"));
    assert.throws(() => selectBuildNumber(["9999.99.99"]));
    for (const value of ["0", "10000", "1.100", "1.0.100", "1\n", "1;echo", "01", "1b1"]) {
        assert.throws(() => parseBuildNumber(value));
    }
});

test("distribution checks enforce expiry, team, bundle, profile kind, certificate membership, and entitlements", () => {
    const options = validateProfile(profile(), signing);
    assert.equal(options.provisioningProfiles[bundleId], "Duo Browser App Store");
    assert.equal(options.manageAppVersionAndBuildNumber, false);
    const changes = [
        value => { value.ExpirationDate = "2020-01-01"; },
        value => { value.ExpirationDate = "invalid"; },
        value => { value.ExpirationDate = 9999; },
        value => { value.TeamIdentifier = ["OTHER"]; },
        value => { value.Entitlements["application-identifier"] = `${teamId}.other`; },
        value => { value.ProvisionedDevices = []; },
        value => { value.ProvisionsAllDevices = true; },
        value => { value.Entitlements["get-task-allow"] = true; },
        value => { value.DeveloperCertificates = []; },
        value => { value.DeveloperCertificates = [Buffer.from("other").toString("base64")]; },
        value => { value.UUID = "../../outside"; }
    ];
    for (const change of changes) {
        const value = profile();
        change(value);
        assert.throws(() => validateProfile(value, signing));
    }
    assert.throws(() => validateProfile(profile(), { ...signing, required: { "aps-environment": "production" } }));
    assert.doesNotThrow(() => validateProfile(profile(), {
        ...signing,
        required: { "keychain-access-groups": ["$(AppIdentifierPrefix)$(CFBundleIdentifier)"] }
    }));
    assert.ok(permitted(["team.app"], ["team.*"]));
    assert.ok(!permitted(["other.app"], ["team.*"]));
});

test("certificate validation masks identity values before native signing can log them", () => {
    const directory = fs.mkdtempSync(path.join(os.tmpdir(), "duo-certificate-"));
    const openssl = process.platform === "win32"
        ? path.join(process.env.ProgramFiles || "C:\\Program Files", "Git", "usr", "bin", "openssl.exe")
        : "openssl";
    try {
        const key = path.join(directory, "fixture.key");
        const certificate = path.join(directory, "fixture.pem");
        cp.execFileSync(openssl, [
            "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
            "-subj", `/CN=Apple Distribution: Fixture (${teamId})/O=Fixture`,
            "-keyout", key, "-out", certificate
        ], { stdio: ["ignore", "pipe", "pipe"] });
        const values = [];
        const parsed = certificateMetadata(fs.readFileSync(certificate, "utf8"), teamId, value => values.push(value));
        assert.ok(parsed.raw.length);
        assert.ok(values.includes(`Apple Distribution: Fixture (${teamId})`));
        assert.ok(values.includes("Fixture"));
        assert.throws(() => certificateMetadata(fs.readFileSync(certificate, "utf8"), "OTHER", () => {}));
    } finally { fs.rmSync(directory, { recursive: true }); }
});

function apiConfig() {
    const { privateKey, publicKey } = crypto.generateKeyPairSync("ec", { namedCurve: "prime256v1" });
    return {
        appId: "6827739657", bundleId, keyId: "FIXTURE",
        issuerId: "00000000-0000-4000-8000-000000000002",
        privateKey: privateKey.export({ type: "pkcs8", format: "pem" }), publicKey
    };
}

test("Apple authentication uses a bounded ES256 team-key JWT without logging a key", () => {
    const config = apiConfig();
    const token = makeToken(config, 1000000);
    const [header, payload, signature] = token.split(".");
    const body = JSON.parse(Buffer.from(payload, "base64url").toString());
    assert.equal(body.iss, config.issuerId);
    assert.equal(body.aud, "appstoreconnect-v1");
    assert.equal(body.exp - body.iat, 900);
    assert.equal(Buffer.from(signature, "base64url").length, 64);
    assert.ok(crypto.verify("sha256", Buffer.from(`${header}.${payload}`),
        { key: config.publicKey, dsaEncoding: "ieee-p1363" }, Buffer.from(signature, "base64url")));
    assert.throws(() => makeToken({ ...config, privateKey: "not a private key" }));
});

function response(data, next = null) {
    return { ok: true, status: 200, json: async () => ({ data, links: { next } }) };
}

test("build lookup verifies the app and follows all permitted build-history pages", async () => {
    const config = apiConfig();
    const requests = [];
    const fetchImpl = async (url, options) => {
        requests.push({ url: String(url), options });
        if (url.pathname.startsWith("/v1/apps/")) return response({ attributes: { bundleId } });
        if (requests.length === 2) {
            return response([{ attributes: { version: "2" } }], "https://api.appstoreconnect.apple.com/v1/builds?cursor=next");
        }
        return response([{ attributes: { version: "1000" } }]);
    };
    assert.equal(await storeBuildNumber(config, fetchImpl), "1000.0.1");
    assert.equal(requests.length, 3);
    assert.equal(requests[0].options.redirect, "error");
    assert.match(requests[0].options.headers.Authorization, /^Bearer /);
    assert.equal(new URL(requests[1].url).searchParams.get("filter[app]"), config.appId);
});

test("metadata lookup fails closed for wrong apps, denied keys, and untrusted pagination", async () => {
    const config = apiConfig();
    await assert.rejects(storeBuildNumber(config, async () => response({ attributes: { bundleId: "other" } })));
    await assert.rejects(storeBuildNumber(config, async () => ({ ok: false, status: 403 })));
    const requests = [];
    await assert.rejects(storeBuildNumber(config, async url => {
        requests.push(String(url));
        if (url.pathname.startsWith("/v1/apps/")) return response({ attributes: { bundleId } });
        return response([], "https://untrusted.invalid/v1/builds");
    }));
    assert.equal(requests.length, 2);
});

test("metadata lookup retries transient transport and server errors without retrying writes", async () => {
    let attempts = 0;
    const config = apiConfig();
    const result = await storeBuildNumber(config, async (url, options) => {
        attempts++;
        assert.equal(options.method, undefined);
        assert.equal(options.redirect, "error");
        assert.equal(url.origin, "https://api.appstoreconnect.apple.com");
        if (attempts === 1) throw new DOMException("Fixture timeout", "TimeoutError");
        if (attempts === 2) return { ok: false, status: 503 };
        if (url.pathname.startsWith("/v1/apps/")) return response({ attributes: { bundleId } });
        return response([{ attributes: { version: "1.0.5" } }]);
    });
    assert.equal(result, "1.0.6");
    assert.equal(attempts, 4);
});

test("metadata retries are bounded and denied credentials are never retried", async () => {
    let transientAttempts = 0;
    await assert.rejects(storeBuildNumber(apiConfig(), async () => {
        transientAttempts++;
        throw new TypeError("Fixture transport failure");
    }));
    assert.equal(transientAttempts, 3);
    let deniedAttempts = 0;
    await assert.rejects(storeBuildNumber(apiConfig(), async () => {
        deniedAttempts++;
        return { ok: false, status: 403 };
    }));
    assert.equal(deniedAttempts, 1);
});

test("entitlement paths cannot escape the reviewed checkout", () => {
    const root = fs.mkdtempSync(path.join(os.tmpdir(), "duo-entitlements-"));
    try {
        const file = path.join(root, "App.entitlements");
        fs.writeFileSync(file, "fixture");
        const settings = value => [{ target: "DuoBrowser", buildSettings: { CODE_SIGN_ENTITLEMENTS: value } }];
        assert.equal(entitlementPath(settings(""), root), "");
        assert.equal(entitlementPath(settings("App.entitlements"), root), fs.realpathSync(file));
        assert.throws(() => entitlementPath(settings("../outside.entitlements"), root));
        assert.throws(() => entitlementPath(settings("$(UNRESOLVED)"), root));
        assert.throws(() => entitlementPath([], root));
    } finally { fs.rmSync(root, { recursive: true }); }
});

test("the pinned SDK selects a matching available iPhone rather than an arbitrary older runtime", () => {
    const available = { devices: {
        "com.apple.CoreSimulator.SimRuntime.iOS-18-5": [{ name: "iPhone", isAvailable: true, udid: "old" }],
        "com.apple.CoreSimulator.SimRuntime.iOS-27-1": [
            { name: "iPad", isAvailable: true, udid: "tablet" },
            { name: "iPhone Duo", isAvailable: false, udid: "unavailable" },
            { name: "iPhone Duo", isAvailable: true, udid: "expected" }
        ]
    } };
    assert.equal(chooseDevice(available, "27.1"), "expected");
    assert.throws(() => chooseDevice(available, "26.0"));
});

test("public summaries contain counts only, never raw test names, errors, or environment content", () => {
    assert.deepEqual(safeSummary({
        passedTests: 2, failedTests: 1, skippedTests: 0,
        testName: "private", deviceName: "private", environment: { secret: "fixture" }
    }), { passedTests: 2, failedTests: 1, skippedTests: 0 });
    assert.throws(() => safeSummary({ passedTests: "2", failedTests: 0, skippedTests: 0 }));
    assert.throws(() => safeSummary({ passedTests: 1, failedTests: 0 }));
});
