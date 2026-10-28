(function () {
    "use strict";
    if (window.duo) return;
    const handler = window.webkit && window.webkit.messageHandlers.duo;
    if (!handler) return;
    const documentId = crypto.randomUUID();
    const subscribers = new Set();
    function send(method, parameters = {}) {
        return handler.postMessage({ version: "1.0", documentId, method, ...parameters });
    }
    window.addEventListener("duo.native", function (event) {
        const detail = event.detail;
        if (!detail || detail.documentId !== documentId || !detail.event) return;
        for (const callback of [...subscribers]) {
            try { callback(Object.freeze(detail.event)); }
            catch (error) { console.error("DuoKit event subscriber failed", error); }
        }
    });
    const api = Object.freeze({
        isAvailable: true,
        version: "1.0",
        controls: Object.freeze({
            set: configuration => send("controls.set", { configuration }),
            update: configuration => send("controls.update", { configuration }),
            clear: () => send("controls.clear")
        }),
        events: Object.freeze({
            subscribe(callback) {
                if (typeof callback !== "function") throw new TypeError("Expected a callback");
                subscribers.add(callback);
                return () => subscribers.delete(callback);
            }
        }),
        device: Object.freeze({ capabilities: () => send("device.capabilities") }),
        scanner: Object.freeze({
            request({ requestId, gestureToken }) {
                return send("scanner.request", { requestId, gestureToken });
            }
        })
    });
    Object.defineProperty(window, "duo", { value: api, writable: false, configurable: false });
}());
