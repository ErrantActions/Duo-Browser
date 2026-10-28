const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const cp = require("node:child_process");

const root = path.join(__dirname, "..");
const ios = fs.readFileSync(path.join(root, ".github", "workflows", "ios.yml"), "utf8");
const release = fs.readFileSync(path.join(root, ".github", "workflows", "testflight.yml"), "utf8");

test("workflow actions use immutable revisions and do not persist checkout credentials", () => {
    for (const workflow of [ios, release]) {
        const actions = [...workflow.matchAll(/uses:\s+([^\s#]+)/g)].map(match => match[1]);
        assert.ok(actions.length);
        for (const action of actions) {
            assert.match(action, /^actions\/(?:checkout|upload-artifact)@[a-f0-9]{40}$/);
        }
        assert.equal((workflow.match(/actions\/checkout@/g) || []).length,
            (workflow.match(/persist-credentials:\s+false/g) || []).length);
        assert.match(workflow, /permissions:\s*\n\s+contents:\s+read/);
        assert.doesNotMatch(workflow, /pull_request_target|write-all|contents:\s*write|id-token:\s*write/);
    }
});

test("unsigned CI does not receive signing secrets and publishes only test results", () => {
    assert.doesNotMatch(ios, /secrets\.|environment:\s*app-store/);
    assert.match(ios, /CODE_SIGNING_ALLOWED=NO/);
    assert.match(ios, /path:\s*\|\s*\n\s+TestResults\.xcresult\s*\n\s+TestAttachments/);
    assert.match(ios, /retention-days:\s*3/);
});

test("signing requires manual confirmation, main, successful tests, and an environment", () => {
    assert.match(release, /workflow_dispatch:/);
    assert.doesNotMatch(release, /^\s+(?:push|pull_request|pull_request_target):/m);
    assert.match(release, /inputs\.confirm_upload && github\.ref == 'refs\/heads\/main'/);
    assert.match(release, /vars\.ENABLE_TESTFLIGHT == 'true'/);
    assert.match(release, /upload:\s*\n\s+needs:\s*verify/);
    assert.match(release, /environment:\s*app-store/);
    assert.match(release, /path:\s*TestResults\.xcresult/);
    assert.doesNotMatch(release, /path:\s*(?:build|\.|~|\$HOME)(?:\s|\/)/);
});

test("signing material is removed from child-process environments before native tools run", () => {
    const bash = process.platform === "win32"
        ? path.join(process.env.ProgramFiles || "C:\\Program Files", "Git", "bin", "bash.exe")
        : "bash";
    const fixture = `
set -euo pipefail
xcrun() {
  for name in APP_STORE_CONNECT_PRIVATE_KEY DISTRIBUTION_CERTIFICATE_BASE64 DISTRIBUTION_CERTIFICATE_PASSWORD PROVISIONING_PROFILE_BASE64; do
    if printenv "$name" >/dev/null; then
      echo "Sensitive signing environment unexpectedly inherited."
      return 99
    fi
  done
  echo "PRIVATE_ENVIRONMENT_REMOVED" >&2
  return 73
}
export -f xcrun
exec bash .github/scripts/testflight.sh
`;
    const result = cp.spawnSync(bash, ["-c", fixture], {
        cwd: root,
        encoding: "utf8",
        env: {
            ...process.env,
            APP_BUNDLE_ID: "com.errantactions.duobrowser",
            APPLE_TEAM_ID: "QM3794NUZS",
            BUILD_NUMBER: "1",
            APP_STORE_CONNECT_KEY_ID: "FIXTURE",
            APP_STORE_CONNECT_ISSUER_ID: "fixture",
            APP_STORE_CONNECT_PRIVATE_KEY: "fixture",
            DISTRIBUTION_CERTIFICATE_BASE64: "fixture",
            DISTRIBUTION_CERTIFICATE_PASSWORD: "fixture",
            PROVISIONING_PROFILE_BASE64: "fixture"
        }
    });
    assert.ifError(result.error);
    assert.equal(result.status, 73, result.stderr);
    assert.match(result.stderr, /PRIVATE_ENVIRONMENT_REMOVED/);
    assert.doesNotMatch(result.stdout + result.stderr, /\bfixture\b/);
});
