(() => {
    "use strict";
    const key = "__duoScannerInput";
    function eligible(field) {
        if (!(field instanceof HTMLInputElement || field instanceof HTMLTextAreaElement)
            || !field.isConnected || field.disabled || field.readOnly
            || (field instanceof HTMLInputElement && !["text", "search", "tel", "url", "email"].includes(field.type))
            || /(?:password|cc-|one-time-code)/i.test(field.autocomplete)
            || field.closest("[hidden],[inert],[aria-hidden='true']")
            || !field.getClientRects().length) return false;
        for (let node = field; node; node = node.parentElement) {
            const style = getComputedStyle(node);
            if (style.display === "none" || style.visibility !== "visible" || Number(style.opacity) === 0) return false;
        }
        return true;
    }
    if (!globalThis[key]) {
        const state = { last: null, ticket: null };
        document.addEventListener("focusin", event => {
            state.last = eligible(event.target) ? event.target : null;
            state.ticket = null;
        }, true);
        globalThis[key] = state;
    }
    const state = globalThis[key];
    if (typeof mode === "undefined") return null;
    if (mode === "clear") {
        if (state.ticket && state.ticket.token === token) {
            if (state.last === state.ticket.field) state.last = null;
            state.ticket = null;
        }
        return true;
    }
    if (mode === "capture") {
        state.ticket = null;
        const active = document.activeElement;
        const field = active && active !== document.body && active !== document.documentElement ? active : state.last;
        if (!eligible(field)) throw new Error("Select an editable text field on the page first. Passwords, payment fields, hidden fields and frames are not supported.");
        const token = crypto.randomUUID();
        state.ticket = {
            token, field, url: location.href, value: field.value, form: field.form,
            start: field.selectionStart, end: field.selectionEnd, time: performance.now()
        };
        return token;
    }
    if (mode !== "apply") throw new Error("Unsupported scanner operation.");
    const ticket = state.ticket;
    state.ticket = null;
    if (!ticket || ticket.token !== token || ticket.url !== sourceURL || location.href !== sourceURL
        || performance.now() - ticket.time > 75000 || document.visibilityState !== "visible"
        || !Number.isFinite(expiresAt) || Date.now() > expiresAt) {
        throw new Error("The scan target expired or the page changed. Select the field and scan again.");
    }
    const field = ticket.field;
    function unchanged() {
        return Date.now() <= expiresAt && document.visibilityState === "visible"
            && location.href === sourceURL && eligible(field) && field.value === ticket.value && field.form === ticket.form;
    }
    if (!unchanged()) throw new Error("The selected field changed. No scanned text was entered.");
    if (typeof value !== "string" || !value.length || value.length > 4096
        || !["selection", "replace", "append"].includes(insertion) || !["none", "enter", "submit"].includes(suffix)) {
        throw new Error("The scanned input or scanner settings are invalid.");
    }
    const form = field.form;
    // Named form controls can shadow action, method and target properties.
    function formInfo() {
        return {
            action: new URL(form.getAttribute("action") || sourceURL, document.baseURI),
            method: (form.getAttribute("method") || "get").toLowerCase(),
            target: (form.getAttribute("target") || document.querySelector("base[target]")?.getAttribute("target") || "_self").toLowerCase()
        };
    }
    const info = suffix === "submit" && form ? formInfo() : null;
    if (suffix === "submit" && (!info || info.action.origin !== location.origin
        || !["https:", "file:"].includes(info.action.protocol) || !["get", "post"].includes(info.method)
        || (info.action.protocol === "file:" && info.action.href !== sourceURL)
        || info.target !== "_self")) {
        throw new Error("Enter and Submit requires a same-site form in this tab. Choose Enter Events for custom website handlers.");
    }
    const start = insertion === "replace" ? 0
        : insertion === "append" ? field.value.length : ticket.start ?? field.value.length;
    const end = insertion === "replace" ? field.value.length
        : insertion === "append" ? field.value.length : ticket.end ?? field.value.length;
    const text = field.value.slice(0, start) + value + field.value.slice(end);
    if (field.maxLength >= 0 && text.length > field.maxLength) throw new Error("The code exceeds this field's maximum length. Nothing was entered.");
    field.focus({ preventScroll: true });
    const accepted = field.dispatchEvent(new InputEvent("beforeinput", {
        bubbles: true, cancelable: true, inputType: "insertText", data: value
    }));
    if (!accepted || !unchanged()) throw new Error("The website canceled input or changed the selected field.");
    const prototype = field instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    const setter = Object.getOwnPropertyDescriptor(prototype, "value").set;
    setter.call(field, text);
    if (field.value !== text) {
        setter.call(field, ticket.value);
        throw new Error("This field cannot preserve the code exactly. Nothing was entered. Choose a plain text field.");
    }
    if (field.selectionStart !== null) field.setSelectionRange(start + value.length, start + value.length);
    field.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: value }));
    field.dispatchEvent(new Event("change", { bubbles: true }));
    if (suffix !== "none") {
        if (Date.now() > expiresAt || document.visibilityState !== "visible"
            || !eligible(field) || location.href !== sourceURL || field.form !== form) {
            throw new Error("Text was entered, but the page changed before Enter could be sent.");
        }
        const options = { bubbles: true, cancelable: true, key: "Enter", code: "Enter", keyCode: 13, which: 13 };
        let proceed = field.dispatchEvent(new KeyboardEvent("keydown", options));
        if (proceed) proceed = field.dispatchEvent(new KeyboardEvent("keypress", options));
        field.dispatchEvent(new KeyboardEvent("keyup", options));
        if (suffix === "submit" && proceed) {
            const current = formInfo();
            if (Date.now() > expiresAt || document.visibilityState !== "visible"
                || location.href !== sourceURL || !eligible(field) || field.form !== form
                || current.action.href !== info.action.href || current.method !== info.method || current.target !== "_self") {
                throw new Error("Text was entered, but the form changed before submission.");
            }
            HTMLFormElement.prototype.requestSubmit.call(form);
        }
    }
    return true;
})()
