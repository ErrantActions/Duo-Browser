const fs = require("node:fs");
const path = require("node:path");
const assert = require("node:assert/strict");
const root = path.join(__dirname, "..");
const text = fs.readFileSync(path.join(root, "DuoBrowser.xcodeproj", "project.pbxproj"), "utf8");
const tokens = text.replace(/\/\*[\s\S]*?\*\//g, "").replace(/\/\/[^\n]*/g, "")
    .match(/"(?:\\.|[^"\\])*"|[{}()=;,]|[^\s{}()=;,]+/g);
let index = 0;
function parse() {
    const token = tokens[index++];
    if (token === "{") {
        const result = {};
        while (tokens[index] !== "}") {
            const key = parse();
            assert.equal(tokens[index++], "=");
            assert.equal(Object.hasOwn(result, key), false, `Duplicate key ${key}`);
            result[key] = parse();
            assert.equal(tokens[index++], ";");
        }
        index++;
        return result;
    }
    if (token === "(") {
        const result = [];
        while (tokens[index] !== ")") {
            result.push(parse());
            if (tokens[index] === ",") index++;
            else assert.equal(tokens[index], ")");
        }
        index++;
        return result;
    }
    assert.ok(token, "Unexpected end of project");
    return token.startsWith('"') ? JSON.parse(token) : token;
}
const project = parse();
assert.equal(index, tokens.length);
const objects = project.objects;
for (const token of tokens) {
    if (/^[A-F0-9]{24}$/.test(token)) assert.ok(objects[token], `Unresolved reference ${token}`);
}
const referencedSources = [];
const resources = [];
function visit(id, base) {
    const object = objects[id];
    if (object.isa === "PBXGroup") {
        const directory = object.path ? path.join(base, object.path) : base;
        for (const child of object.children) visit(child, directory);
    } else if (object.isa === "PBXFileReference" && object.sourceTree === "<group>") {
        const file = path.join(base, object.path);
        assert.ok(fs.existsSync(file), `Missing project file ${file}`);
        if (file.endsWith(".swift")) referencedSources.push(id);
        if (["duo.js", "AskDuoContext.js", "ScannerInput.js", "Demo", "PrivacyInfo.xcprivacy", "Assets.xcassets"].includes(object.path)) resources.push(id);
    }
}
visit(objects[project.rootObject].mainGroup, root);
const memberships = Object.values(objects).filter(object => object.isa === "PBXSourcesBuildPhase")
    .flatMap(object => object.files).map(id => objects[id].fileRef);
assert.equal(memberships.length, referencedSources.length);
for (const id of referencedSources) assert.equal(memberships.filter(item => item === id).length, 1);
const resourceMemberships = Object.values(objects).filter(object => object.isa === "PBXResourcesBuildPhase")
    .flatMap(object => object.files).map(id => objects[id].fileRef);
assert.equal(resources.length, 6);
for (const id of resources) assert.equal(resourceMemberships.filter(item => item === id).length, 1);
function countSources(directory) {
    return fs.readdirSync(directory, { withFileTypes: true }).reduce((sum, entry) => {
        const file = path.join(directory, entry.name);
        return sum + (entry.isDirectory() ? countSources(file) : Number(file.endsWith(".swift")));
    }, 0);
}
const directories = ["DuoBrowser", "DuoBrowserTests", "DuoBrowserUITests"];
const count = directories.reduce((sum, directory) => sum + countSources(path.join(root, directory)), 0);
assert.equal(count, referencedSources.length, "Every Swift file must be in the project");
const icon = fs.readFileSync(path.join(root, "DuoBrowser", "Resources", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png"));
assert.equal(icon.readUInt32BE(16), 1024);
assert.equal(icon.readUInt32BE(20), 1024);
assert.equal(icon[25], 2, "The app icon must use RGB without an alpha channel");
console.log(`PASS: Project parses; references resolve; ${count} Swift files and all SDK/demo/privacy resources have build membership.`);
