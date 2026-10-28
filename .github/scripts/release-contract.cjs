const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");

const APPLE_API = "https://api.appstoreconnect.apple.com";
class ReleaseError extends Error {}

function parseBuildNumber(value) {
    if (typeof value !== "string" || !/^[1-9]\d{0,3}(?:\.(?:0|[1-9]\d?)){0,2}$/.test(value)) {
        throw new ReleaseError("Build numbers must use 1-9999 with up to two 0-99 components.");
    }
    const [major, minor = 0, patch = 0] = value.split(".").map(Number);
    return major * 10000 + minor * 100 + patch;
}

function selectBuildNumber(existing, override = "") {
    if (!Array.isArray(existing) || typeof override !== "string") throw new ReleaseError("Invalid build-number inputs.");
    const maximum = existing.reduce((max, value) => Math.max(max, parseBuildNumber(value)), 0);
    if (override.trim()) {
        const requested = override.trim();
        if (parseBuildNumber(requested) <= maximum) {
            throw new ReleaseError("The requested build number does not exceed existing App Store Connect uploads.");
        }
        return requested;
    }
    const next = maximum ? maximum + 1 : 10000;
    const major = Math.floor(next / 10000);
    const minor = Math.floor(next / 100) % 100;
    const patch = next % 100;
    if (major > 9999) throw new ReleaseError("Build numbering is exhausted; review the versioning policy.");
    return patch ? `${major}.${minor}.${patch}` : minor ? `${major}.${minor}` : `${major}`;
}

function permitted(requested, granted) {
    if (typeof requested === "string" && typeof granted === "string") {
        const pattern = granted.split("*").map(part => part.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")).join(".*");
        return new RegExp(`^${pattern}$`).test(requested);
    }
    if (Array.isArray(requested) && Array.isArray(granted)) {
        return requested.every(value => granted.some(candidate => permitted(value, candidate)));
    }
    if (requested && granted && typeof requested === "object" && typeof granted === "object"
        && !Array.isArray(requested) && !Array.isArray(granted)) {
        return Object.entries(requested).every(([key, value]) => permitted(value, granted[key]));
    }
    return requested === granted;
}

function validateProfile(profile, { teamId, bundleId, required = {}, certificateDER, now = Date.now() }) {
    const entitlements = profile.Entitlements;
    const expiry = typeof profile.ExpirationDate === "string" ? Date.parse(profile.ExpirationDate) : NaN;
    if (!Array.isArray(profile.TeamIdentifier) || profile.TeamIdentifier.length !== 1
        || profile.TeamIdentifier[0] !== teamId
        || !entitlements || entitlements["application-identifier"] !== `${teamId}.${bundleId}`) {
        throw new ReleaseError("The provisioning profile does not match Duo's team and bundle identifier.");
    }
    if (!Number.isFinite(expiry) || expiry <= now) throw new ReleaseError("The provisioning profile is expired or has no valid expiry.");
    if (Object.hasOwn(profile, "ProvisionedDevices") || profile.ProvisionsAllDevices
        || entitlements["get-task-allow"]) {
        throw new ReleaseError("An App Store Connect profile is required, not development, ad hoc, or enterprise.");
    }
    if (typeof profile.Name !== "string" || !profile.Name.trim()
        || !/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(profile.UUID || "")
        || !Array.isArray(profile.DeveloperCertificates) || !profile.DeveloperCertificates.length) {
        throw new ReleaseError("The profile is missing required distribution metadata.");
    }
    if (!profile.DeveloperCertificates.some(value =>
        typeof value === "string" && Buffer.from(value, "base64").equals(certificateDER))) {
        throw new ReleaseError("The P12 certificate is not authorized by this provisioning profile.");
    }
    const expanded = JSON.parse(JSON.stringify(required)
        .replace(/\$\(AppIdentifierPrefix\)|\$\(TeamIdentifierPrefix\)/g, `${teamId}.`)
        .replace(/\$\(CFBundleIdentifier\)|\$\(PRODUCT_BUNDLE_IDENTIFIER\)/g, bundleId));
    if (!permitted(expanded, entitlements)) throw new ReleaseError("The profile does not grant the app's required entitlements.");
    return {
        method: "app-store-connect", destination: "export", signingStyle: "manual",
        teamID: teamId, signingCertificate: "Apple Distribution",
        provisioningProfiles: { [bundleId]: profile.Name },
        manageAppVersionAndBuildNumber: false, uploadSymbols: true
    };
}

function mask(value) {
    if (!value) return;
    process.stdout.write(`::add-mask::${value.replace(/%/g, "%25").replace(/\r/g, "%0D").replace(/\n/g, "%0A")}\n`);
}

function certificateMetadata(pem, teamId, maskValue = mask) {
    if ((pem.match(/-----BEGIN CERTIFICATE-----/g) || []).length !== 1) {
        throw new ReleaseError("The P12 must provide exactly one signing certificate.");
    }
    let certificate;
    try { certificate = new crypto.X509Certificate(pem); }
    catch { throw new ReleaseError("The distribution certificate could not be parsed."); }
    const commonName = certificate.subject.split("\n").find(line => line.startsWith("CN="))?.slice(3);
    const organization = certificate.subject.split("\n").find(line => line.startsWith("O="))?.slice(2);
    maskValue(commonName);
    maskValue(organization);
    maskValue(commonName?.replace(/^Apple Distribution: /, "").replace(new RegExp(` \\(${teamId}\\)$`), ""));
    if (!commonName?.startsWith("Apple Distribution: ") || !commonName.endsWith(`(${teamId})`)) {
        throw new ReleaseError("A matching Apple Distribution certificate is required.");
    }
    if (!Number.isFinite(Date.parse(certificate.validFrom)) || !Number.isFinite(Date.parse(certificate.validTo))
        || Date.parse(certificate.validFrom) > Date.now() || Date.parse(certificate.validTo) <= Date.now()) {
        throw new ReleaseError("The distribution certificate is expired or not yet valid.");
    }
    return certificate;
}

function makeToken({ keyId, issuerId, privateKey }, now = Date.now()) {
    if (!/^[A-Z0-9]{1,20}$/.test(keyId || "")
        || !/^[a-f0-9]{8}(?:-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(issuerId || "")) {
        throw new ReleaseError("Valid App Store Connect team-key and issuer identifiers are required.");
    }
    let key;
    try { key = crypto.createPrivateKey(privateKey); }
    catch { throw new ReleaseError("The App Store Connect private key could not be parsed."); }
    if (key.asymmetricKeyType !== "ec" || key.asymmetricKeyDetails?.namedCurve !== "prime256v1") {
        throw new ReleaseError("App Store Connect requires a P-256 team API upload key, not an APNs configuration.");
    }
    const iat = Math.floor(now / 1000);
    const header = Buffer.from(JSON.stringify({ alg: "ES256", kid: keyId, typ: "JWT" })).toString("base64url");
    const payload = Buffer.from(JSON.stringify({ iss: issuerId, iat, exp: iat + 900, aud: "appstoreconnect-v1" })).toString("base64url");
    const unsigned = `${header}.${payload}`;
    const signature = crypto.sign("sha256", Buffer.from(unsigned), { key, dsaEncoding: "ieee-p1363" });
    return `${unsigned}.${signature.toString("base64url")}`;
}

async function storeBuildNumber(config, fetchImpl = fetch) {
    if (!/^[1-9]\d+$/.test(config.appId || "")) throw new ReleaseError("A valid App Store Connect app identifier is required.");
    const token = makeToken(config);
    async function read(url) {
        const target = new URL(url, APPLE_API);
        if (target.origin !== APPLE_API || target.username || target.password) {
            throw new ReleaseError("Refusing an unexpected App Store Connect pagination origin.");
        }
        const response = await fetchImpl(target, {
            headers: { Authorization: `Bearer ${token}`, Accept: "application/json" },
            redirect: "error", signal: AbortSignal.timeout(20000)
        });
        if (!response.ok) throw new ReleaseError(`App Store Connect metadata lookup failed (HTTP ${response.status}). Verify a team upload key, issuer, and app access.`);
        return response.json();
    }
    const app = await read(`/v1/apps/${config.appId}?fields[apps]=bundleId`);
    if (app.data?.attributes?.bundleId !== config.bundleId) throw new ReleaseError("The App Store Connect app is not Duo's bundle.");
    let url = `/v1/builds?filter[app]=${config.appId}&limit=200&fields[builds]=version`;
    const versions = [];
    for (let page = 0; url; page++) {
        if (page >= 20) throw new ReleaseError("Unable to enumerate the entire build history within the safety limit.");
        const result = await read(url);
        if (!Array.isArray(result.data)) throw new ReleaseError("Invalid App Store Connect build response.");
        for (const build of result.data) {
            parseBuildNumber(build.attributes?.version);
            versions.push(build.attributes.version);
        }
        const next = result.links?.next;
        if (next != null && typeof next !== "string") throw new ReleaseError("Invalid App Store Connect pagination.");
        if (next && !new URL(next, APPLE_API).pathname.startsWith("/v1/builds")) throw new ReleaseError("Unexpected build pagination path.");
        url = next;
    }
    return selectBuildNumber(versions, config.override || "");
}

function entitlementPath(settings, root) {
    const app = settings.find(item => item.target === "DuoBrowser")?.buildSettings;
    if (!app) throw new ReleaseError("DuoBrowser build settings are missing.");
    const value = app.CODE_SIGN_ENTITLEMENTS;
    if (!value) return "";
    if (typeof value !== "string" || value.includes("$(")) throw new ReleaseError("Unresolved entitlement path.");
    const file = path.resolve(root, value);
    if (!file.startsWith(path.resolve(root) + path.sep)) throw new ReleaseError("Entitlements must be inside the reviewed checkout.");
    const real = fs.realpathSync(file);
    if (!real.startsWith(fs.realpathSync(root) + path.sep)) throw new ReleaseError("Entitlement symlinks must stay inside the reviewed checkout.");
    return real;
}

async function main() {
    const [command, ...args] = process.argv.slice(2);
    const readJSON = file => JSON.parse(fs.readFileSync(file, "utf8"));
    if (command === "entitlements-path") {
        process.stdout.write(entitlementPath(readJSON(args[0]), process.cwd()));
    } else if (command === "validate-profile") {
        const certificate = certificateMetadata(fs.readFileSync(args[1], "utf8"), process.env.APPLE_TEAM_ID);
        const options = validateProfile(readJSON(args[0]), {
            teamId: process.env.APPLE_TEAM_ID, bundleId: process.env.APP_BUNDLE_ID,
            required: readJSON(args[2]), certificateDER: certificate.raw
        });
        if (args[3]) fs.writeFileSync(args[3], JSON.stringify(options));
        console.log("Distribution certificate, profile, expiry, app/team, and required entitlements passed.");
    } else if (command === "build-number") {
        const number = await storeBuildNumber({
            appId: process.env.APP_STORE_CONNECT_APP_ID, bundleId: process.env.APP_BUNDLE_ID,
            keyId: process.env.APP_STORE_CONNECT_KEY_ID, issuerId: process.env.APP_STORE_CONNECT_ISSUER_ID,
            privateKey: process.env.APP_STORE_CONNECT_PRIVATE_KEY, override: process.env.BUILD_NUMBER_OVERRIDE
        });
        if (!process.env.GITHUB_OUTPUT) throw new ReleaseError("GitHub output file is required.");
        fs.appendFileSync(process.env.GITHUB_OUTPUT, `build_number=${number}\n`);
        console.log(`Validated next TestFlight build number: ${number}`);
    } else if (command === "check-archive") {
        const info = readJSON(args[0]);
        if (info.CFBundleIdentifier !== process.env.APP_BUNDLE_ID || info.CFBundleVersion !== process.env.BUILD_NUMBER) {
            throw new ReleaseError("The signed archive has an unexpected app identity or build number.");
        }
        console.log("Archive app identity and build number verified.");
    } else {
        throw new ReleaseError("Unknown release contract command.");
    }
}

module.exports = {
    parseBuildNumber, selectBuildNumber, permitted, validateProfile,
    certificateMetadata, makeToken, storeBuildNumber, entitlementPath
};
if (require.main === module) main().catch(error => {
    // Do not echo arbitrary transport/crypto errors that could contain credentials.
    console.error(error instanceof ReleaseError ? error.message : "Release preflight could not read metadata or contact Apple. No private diagnostic output was logged.");
    process.exitCode = 1;
});
