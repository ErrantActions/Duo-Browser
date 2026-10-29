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
    if (mode === "clear") { state.ticket = null; state.last = null; return true; }
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
        || performance.now() - ticket.time > 75000 || document.visibilityState !== "visible") {
        throw new Error("The scan target expired or the page changed. Select the field and scan again.");
    }
    const field = ticket.field;
    function unchanged() {
        return location.href === sourceURL && eligible(field) && field.value === ticket.value && field.form === ticket.form;
    }
    if (!unchanged()) throw new Error("The selected field changed. No scanned text was entered.");
    if (typeof value !== "string" || !value.length || value.length > 4096
        || !["selection", "replace", "append"].includes(insertion) || !["none", "enter", "submit"].includes(suffix)) {
        throw new Error("The scanned input or scanner settings are invalid.");
    }
    const form = field.form;
    const action = form ? new URL(form.action, location.href) : null;
    if (suffix === "submit" && (!form || action.origin !== location.origin
        || !["https:", "file:"].includes(action.protocol) || !["get", "post"].includes(form.method.toLowerCase())
        || (action.protocol === "file:" && action.href !== sourceURL)
        || (form.target && form.target !== "_self"))) {
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
    Object.getOwnPropertyDescriptor(prototype, "value").set.call(field, text);
    if (field.selectionStart !== null) field.setSelectionRange(start + value.length, start + value.length);
    field.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: value }));
    field.dispatchEvent(new Event("change", { bubbles: true }));
    if (suffix !== "none") {
        if (!eligible(field) || location.href !== sourceURL || field.form !== form) {
            throw new Error("Text was entered, but the page changed before Enter could be sent.");
        }
        const options = { bubbles: true, cancelable: true, key: "Enter", code: "Enter", keyCode: 13, which: 13 };
        let proceed = field.dispatchEvent(new KeyboardEvent("keydown", options));
        if (proceed) proceed = field.dispatchEvent(new KeyboardEvent("keypress", options));
        field.dispatchEvent(new KeyboardEvent("keyup", options));
        if (suffix === "submit" && proceed) {
            if (location.href !== sourceURL || !eligible(field) || field.form !== form || form.action !== action.href
                || !["get", "post"].includes(form.method.toLowerCase()) || (form.target && form.target !== "_self")) {
                throw new Error("Text was entered, but the form changed before submission.");
            }
            HTMLFormElement.prototype.requestSubmit.call(form);
        }
    }
    return true;
})()
