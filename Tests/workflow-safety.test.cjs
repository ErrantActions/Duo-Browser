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

test("both builds are manual, use a standard pinned Xcode runner, and export only optional sanitized counts", () => {
    for (const workflow of [ios, release]) {
        assert.doesNotMatch(workflow, /^\s+(?:push|pull_request|pull_request_target):/m);
        assert.match(workflow, /workflow_dispatch:/);
        assert.match(workflow, /runs-on:\s*xcode-27/);
        assert.match(workflow, /DEVELOPER_DIR:\s*\/Applications\/Xcode_27\.1\.app\/Contents\/Developer/);
        assert.match(workflow, /EXPECTED_IOS_SDK:\s*"27\.1"/);
        assert.match(workflow, /if:\s*always\(\) && inputs\.save_summary/);
        assert.match(workflow, /path:\s*ci-summary\/test-counts\.json/);
        assert.match(workflow, /retention-days:\s*1/);
        assert.doesNotMatch(workflow, /path:\s*(?:\||build\/|TestResults|TestAttachments|~|\$HOME)/);
    }
});

test("unsigned CI does not receive signing secrets", () => {
    assert.doesNotMatch(ios, /secrets\.|environment:\s*app-store/);
    const runner = fs.readFileSync(path.join(root, ".github", "scripts", "test-ios.sh"), "utf8");
    assert.match(runner, /CODE_SIGNING_ALLOWED=NO/);
});

test("signing requires manual confirmation, main, successful tests, and an environment", () => {
    assert.match(release, /workflow_dispatch:/);
    assert.doesNotMatch(release, /^\s+(?:push|pull_request|pull_request_target):/m);
    assert.match(release, /inputs\.confirm_upload && github\.ref == 'refs\/heads\/main'/);
    assert.match(release, /vars\.ENABLE_TESTFLIGHT == 'true'/);
    assert.match(release, /environment:\s*app-store/);
    assert.equal((release.match(/run: bash \.github\/scripts\/test-ios\.sh/g) || []).length, 1);
    assert.match(release, /run: bash \.github\/scripts\/test-ios\.sh unit/);
    assert.match(ios, /run: bash \.github\/scripts\/test-ios\.sh "\$NATIVE_TEST_SUITE"/);
    assert.match(ios, /NATIVE_TEST_SUITE: \$\{\{ inputs\.test_scope \}\}/);
    assert.ok(release.indexOf("testflight.sh preflight") < release.indexOf("test-ios.sh"));
    assert.ok(release.indexOf("test-ios.sh") < release.indexOf("testflight.sh upload"));
    assert.match(release, /steps\.preflight\.outputs\.build_number/);
    assert.doesNotMatch(release, /github\.run_number/);
});

test("release runs every native unit test while full validation still includes UI tests", () => {
    const bash = process.platform === "win32"
        ? path.join(process.env.ProgramFiles || "C:\\Program Files", "Git", "bin", "bash.exe")
        : "bash";
    const fixture = `
set -euo pipefail
xcodebuild() { printf 'XCODE_ARG<%s>\\n' "$@"; }
xcrun() {
  if [[ "$1" == --sdk ]]; then echo 27.1
  elif [[ "$2" == list ]]; then
    printf '%s\\n' '{"devices":{"fixture.iOS-27-1":[{"name":"iPhone","isAvailable":true,"udid":"fixture-device"}]}}'
  elif [[ "$2" == bootstatus ]]; then echo BOOT_SIMULATOR
  else return 99
  fi
}
mkdir() { :; }
defaults() {
  [[ "$*" == "write com.apple.iphonesimulator ConnectHardwareKeyboard -bool NO" ]] || return 99
  echo ONSCREEN_KEYBOARD
}
export -f xcodebuild xcrun mkdir defaults
exec bash .github/scripts/test-ios.sh "$SUITE"
`;
    for (const suite of ["unit", "all", "duo-panel", "ask-duo", "reading", "invalid"]) {
        const result = cp.spawnSync(bash, ["-c", fixture], {
            cwd: root, encoding: "utf8",
            env: { ...process.env, SUITE: suite, EXPECTED_IOS_SDK: "27.1" }
        });
        assert.ifError(result.error);
        if (suite === "invalid") {
            assert.notEqual(result.status, 0);
            assert.doesNotMatch(result.stdout, /XCODE_ARG/);
        } else {
            assert.equal(result.status, 0, result.stderr);
            assert.match(result.stdout, /XCODE_ARG<CODE_SIGNING_ALLOWED=NO>/);
            assert.match(result.stdout, /XCODE_ARG<build-for-testing>/);
            assert.match(result.stdout, /XCODE_ARG<test-without-building>/);
            assert.ok(result.stdout.indexOf("XCODE_ARG<build-for-testing>") < result.stdout.indexOf("BOOT_SIMULATOR"));
            assert.ok(result.stdout.indexOf("BOOT_SIMULATOR") < result.stdout.indexOf("XCODE_ARG<test-without-building>"));
            if (suite === "unit") assert.doesNotMatch(result.stdout, /ONSCREEN_KEYBOARD/);
            else {
                assert.match(result.stdout, /ONSCREEN_KEYBOARD/);
                assert.ok(result.stdout.indexOf("ONSCREEN_KEYBOARD") < result.stdout.indexOf("BOOT_SIMULATOR"));
            }
            if (suite === "unit") assert.match(result.stdout, /XCODE_ARG<-only-testing:DuoBrowserTests>/);
            else if (suite === "duo-panel") {
                assert.match(result.stdout, /XCODE_ARG<-only-testing:DuoBrowserUITests\/BrowserUITests\/testDuoNativeToolbarKeepsWebsiteVisibleAndDeliversNavigation>/);
                assert.doesNotMatch(result.stdout, /XCODE_ARG<-only-testing:DuoBrowserTests>/);
            } else if (suite === "ask-duo") {
                assert.match(result.stdout, /XCODE_ARG<-only-testing:DuoBrowserUITests\/BrowserUITests\/testAskDuoBlocksPrivateTabs>/);
                assert.match(result.stdout, /XCODE_ARG<-only-testing:DuoBrowserUITests\/BrowserUITests\/testAskDuoRequiresConsentAndConfirmsNavigation>/);
                assert.doesNotMatch(result.stdout, /XCODE_ARG<-only-testing:DuoBrowserTests>/);
            } else if (suite === "reading") {
                assert.match(result.stdout, /XCODE_ARG<-only-testing:DuoBrowserUITests\/BrowserUITests\/testReadingViewAppearanceAndPDF>/);
                assert.match(result.stdout, /XCODE_ARG<-only-testing:DuoBrowserUITests\/BrowserUITests\/testReadingViewPrivateExportRequiresConfirmation>/);
                assert.match(result.stdout, /XCODE_ARG<-only-testing:DuoBrowserUITests\/BrowserUITests\/testFavoriteCanBeSavedAndOpenedFromTheStartPage>/);
                assert.doesNotMatch(result.stdout, /XCODE_ARG<-only-testing:DuoBrowserTests>/);
            } else assert.doesNotMatch(result.stdout, /only-testing|skip-testing/);
            assert.match(result.stdout, new RegExp(`XCODE_ARG<-maximum-test-execution-time-allowance>\\nXCODE_ARG<${["all", "ask-duo", "reading"].includes(suite) ? 300 : 180}>`));
        }
    }
});

test("local signing setup preserves main-only access without requiring a second deployment review", () => {
    const helper = fs.readFileSync(path.join(root, "Tools", "Set-TestFlightSecrets.ps1"), "utf8");
    assert.match(helper, /\$environment\.can_admins_bypass -ne \$false/);
    assert.match(helper, /\$policies\.total_count -ne 1/);
    assert.match(helper, /\$policies\.branch_policies\[0\]\.name -ne 'main'/);
    assert.match(helper, /\$policies\.branch_policies\[0\]\.type -ne 'branch'/);
    assert.doesNotMatch(helper, /required_reviewers|reviewer\.id|api --method PUT/);
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
            APP_STORE_CONNECT_APP_ID: "6827739657",
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
