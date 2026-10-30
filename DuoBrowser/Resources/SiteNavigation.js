(() => {
    "use strict";
    const key = "__duoSiteNavigation";
    if (!Object.hasOwn(globalThis, key)) {
        Object.defineProperty(globalThis, key, {
            value: { documentID: crypto.randomUUID(), observer: null, timer: null, lastSent: 0 }
        });
    }
    const state = globalThis[key];
    function pause() {
        state.observer?.disconnect();
        state.observer = null;
        if (state.timer !== null) clearTimeout(state.timer);
        state.timer = null;
    }
    if (typeof mode === "undefined") {
        addEventListener("pagehide", pause, { once: true });
        return null;
    }
    if (mode === "pause") { pause(); return true; }
    if (mode === "watch") {
        if (!state.observer && document.documentElement) {
            state.observer = new MutationObserver(() => {
                if (state.timer !== null) return;
                state.timer = setTimeout(() => {
                    state.timer = null;
                    state.lastSent = performance.now();
                    if (location.href.length > 4096) return;
                    webkit.messageHandlers.siteNavigation.postMessage({
                        documentID: state.documentID, url: location.href
                    });
                }, Math.max(500, 2000 - (performance.now() - state.lastSent)));
            });
            state.observer.observe(document.documentElement, {
                subtree: true, childList: true, characterData: true, attributes: true,
                attributeFilter: ["href", "aria-label", "aria-current", "aria-expanded", "hidden", "style", "class"]
            });
        }
        return true;
    }
    const source = new URL(location.href);
    const demo = allowDemo === true && source.protocol === "file:";
    function visible(node) {
        if (!node.getClientRects().length) return false;
        let item = node;
        for (let depth = 0; item && depth < 64; depth++, item = item.parentElement) {
            const style = getComputedStyle(item);
            if (style.display === "none" || style.visibility !== "visible" || Number(style.opacity) === 0) return false;
        }
        return !item && !node.closest("form,[contenteditable],[hidden],[inert],[aria-hidden='true']");
    }
    const unsafe = /(?:^|[\s/_-])(logout|log-out|signout|sign-out|delete|remove|destroy|checkout|purchase|buy|unsubscribe|disconnect|revoke)(?:$|[\s/?#_-])/i;
    const unsafeQuery = /^(action|cmd|command|do|delete|logout|signout|submit|token|auth|csrf|session)$/i;
    function link(anchor) {
        if (anchor.tagName !== "A" || !anchor.hasAttribute("href") || !visible(anchor)
            || anchor.hasAttribute("download") || anchor.getAttribute("aria-disabled") === "true"
            || anchor.getAttribute("role") === "button"
            || anchor.querySelector("input,textarea,select,button,[contenteditable]")) return null;
        const target = anchor.getAttribute("target") || document.querySelector("base[target]")?.getAttribute("target") || "_self";
        if (target.toLowerCase() !== "_self") return null;
        let url;
        try { url = new URL(anchor.getAttribute("href"), document.baseURI); }
        catch { return null; }
        if (url.username || url.password || url.href.length > 1024 || url.origin !== source.origin) return null;
        if (demo ? url.protocol !== "file:" || url.pathname !== source.pathname || url.search !== source.search : url.protocol !== "https:") return null;
        if ([...url.searchParams.keys()].some(name => unsafeQuery.test(name))) return null;
        const label = Array.from((anchor.getAttribute("aria-label") || anchor.innerText || anchor.getAttribute("title") || "")
            .replace(/\s+/g, " ").trim()).slice(0, 48).join("");
        let pathname;
        try { pathname = decodeURIComponent(url.pathname); }
        catch { return null; }
        if (!label || unsafe.test(label + " " + pathname)) return null;
        return { href: url.href, label };
    }
    function links(root) {
        const walker = document.createTreeWalker(root, NodeFilter.SHOW_ELEMENT);
        const result = [], seen = new Set();
        for (let count = 0, node; count < 400 && (node = walker.nextNode()); count++) {
            const item = link(node);
            if (item && !seen.has(item.href)) { seen.add(item.href); result.push(item); }
            if (result.length === 12) break;
        }
        return result;
    }
    function extract() {
        if (!document.body || (!demo && source.protocol !== "https:")) return [];
        const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_ELEMENT);
        const candidates = [];
        for (let count = 0, node; count < 4000 && (node = walker.nextNode()); count++) {
            const semantic = node.tagName === "NAV" || (node.getAttribute("role") || "").split(/\s+/).includes("navigation");
            if (!semantic && node.tagName !== "HEADER") continue;
            if (!visible(node) || node.closest("main,article,aside,footer")) continue;
            const name = node.getAttribute("aria-label") || "";
            if (/breadcrumb|pagination|social|footer|secondary|table of contents/i.test(name)) continue;
            const items = links(node);
            if (items.length < (semantic ? 2 : 3)) continue;
            let score = semantic ? 6 : 4;
            if (node.closest("header")) score += 2;
            if (/primary|main|site/i.test(name)) score += 4;
            candidates.push({ score, items });
            if (candidates.length === 20) break;
        }
        candidates.sort((a, b) => b.score - a.score);
        if (!candidates.length) return [];
        if (candidates[1]?.score === candidates[0].score) {
            const first = candidates[0].items.map(item => item.href).sort().join("\n");
            const second = candidates[1].items.map(item => item.href).sort().join("\n");
            if (first !== second) return [];
        }
        return candidates[0].items;
    }
    if (mode === "validate") {
        return location.href === sourceURL && state.documentID === documentID
            && extract().some(item => item.href === new URL(href).href);
    }
    if (mode !== "capture") throw new Error("Unsupported site navigation operation.");
    return JSON.stringify({ url: location.href, documentID: state.documentID, links: extract() });
})()
