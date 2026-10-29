const excluded = "form,input,textarea,select,option,button,[contenteditable],[role='form'],[role='textbox'],[role='searchbox'],[role='combobox'],[role='spinbutton'],script,style,noscript,iframe,[hidden],[aria-hidden='true'],[inert]";
function visible(element) {
    if (!element || element.closest(excluded) || !element.getClientRects().length) return false;
    let depth = 0;
    for (let node = element; node; node = node.parentElement) {
        if (++depth > 64) return false;
        const style = getComputedStyle(node);
        if (style.display === "none" || style.visibility !== "visible" || Number(style.opacity) === 0) return false;
    }
    return true;
}
function readable(root, limit) {
    if (!root) return { text: "", truncated: false };
    const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    const parts = [];
    let length = 0, visited = 0, truncated = false;
    for (let node = walker.nextNode(); node; node = walker.nextNode()) {
        if (++visited > 5000) { truncated = true; break; }
        if (!visible(node.parentElement)) continue;
        const value = node.textContent.slice(0, limit * 2).replace(/\s+/g, " ").trim();
        if (!value) continue;
        const remaining = limit - length;
        if (remaining <= 0) { truncated = true; break; }
        parts.push(value.slice(0, remaining));
        length += value.length + 1;
        if (value.length >= remaining) { truncated = true; break; }
    }
    return { text: parts.join(" ").slice(0, limit), truncated };
}
function eligibleLink(anchor) {
    return anchor.tagName === "A" && visible(anchor) && !anchor.hasAttribute("download")
        && anchor.getAttribute("role") !== "button";
}
if (mode === "validate") {
    if (location.href !== sourceURL || globalThis.__askDuoDocumentID !== documentID) return false;
    for (let index = 0; index < Math.min(document.links.length, 5000); index++) {
        const anchor = document.links[index];
        if (eligibleLink(anchor) && anchor.href === href) return true;
    }
    return false;
}
if (mode !== "capture") throw new Error("Unsupported context operation.");
if (!globalThis.__askDuoDocumentID) globalThis.__askDuoDocumentID = crypto.randomUUID();
const main = document.querySelector("main,article,[role='main']");
const root = main && visible(main) ? main : document.body;
const excerpt = readable(root, 1800);
const links = [], seen = new Set();
const collections = root === document.body ? [document.links] : [root.getElementsByTagName("a"), document.links];
for (const candidates of collections) {
    for (let index = 0; index < Math.min(candidates.length, 200) && links.length < 12; index++) {
        const anchor = candidates[index];
        if (!eligibleLink(anchor) || anchor.href.length > 1024 || seen.has(anchor.href)) continue;
        const url = new URL(anchor.href);
        if (url.protocol !== "https:" || url.username || url.password) continue;
        seen.add(anchor.href);
        links.push({ label: readable(anchor, 60).text || url.hostname, href: anchor.href });
    }
}
return JSON.stringify({
    url: location.href,
    documentID: globalThis.__askDuoDocumentID,
    title: document.title.slice(0, 80),
    text: excerpt.text,
    truncated: excerpt.truncated,
    links
});
