function chooseDevice(available, sdkVersion) {
    if (!/^\d+\.\d+$/.test(sdkVersion || "")) throw new Error("An explicit iOS SDK version is required.");
    const suffix = `iOS-${sdkVersion.replace(".", "-")}`;
    const devices = Object.entries(available.devices || {})
        .filter(([runtime]) => runtime.endsWith(suffix))
        .flatMap(([, devices]) => devices)
        .filter(device => device.isAvailable && device.name.startsWith("iPhone"));
    devices.sort((left, right) => Number(right.name === "iPhone Duo") - Number(left.name === "iPhone Duo"));
    if (!devices.length || typeof devices[0].udid !== "string") {
        throw new Error("No available iPhone simulator matches the pinned iOS SDK.");
    }
    return devices[0].udid;
}

module.exports = { chooseDevice };
if (require.main === module) {
    const chunks = [];
    process.stdin.on("data", chunk => chunks.push(chunk));
    process.stdin.on("end", () => {
        try {
            process.stdout.write(chooseDevice(JSON.parse(Buffer.concat(chunks).toString()), process.env.EXPECTED_IOS_SDK));
        } catch {
            console.error("Simulator selection failed. Verify the pinned Xcode/SDK and available iPhone runtime.");
            process.exitCode = 1;
        }
    });
}
