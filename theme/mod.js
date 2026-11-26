// Fumefy: a theme mod that runs inside the Spotify desktop app.
// window.__MOD.groups and window.__MOD.baseCss are filled in by inject.mjs.
// Each part of the UI (theme, friend panel, player, ...) has a design; when a part offers more than one,
// the user can switch between them from the panel. Everything else is fixed and the same in every theme.
const M = window.__MOD;
const root = document.documentElement;
const $ = (s, r = document) => r.querySelector(s);
const esc = (s) => String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
const cleanups = [];

const ICON = `<svg role="img" aria-hidden="true" viewBox="0 0 24 24" width="16" height="16" fill="currentColor"><path d="M12 2C6.49 2 2 6.49 2 12s4.49 10 10 10a2.5 2.5 0 0 0 2.5-2.5c0-.61-.23-1.2-.64-1.67a.53.53 0 0 1-.13-.33c0-.28.22-.5.5-.5H16c3.31 0 6-2.69 6-6 0-4.96-4.49-9-10-9Zm5.5 11a1.5 1.5 0 1 1 0-3 1.5 1.5 0 0 1 0 3Zm-3-4a1.5 1.5 0 1 1 0-3 1.5 1.5 0 0 1 0 3ZM5 11.5a1.5 1.5 0 1 1 3 0 1.5 1.5 0 0 1-3 0Zm6-4a1.5 1.5 0 1 1-3 0 1.5 1.5 0 0 1 3 0Z"/></svg>`;

function styleEl(id) {
  let s = document.getElementById(id);
  if (!s) { s = document.createElement("style"); s.id = id; }
  document.head.appendChild(s); // always last, so it wins over Spotify's styles
  return s;
}

/* ---------- Fixed settings (same in every theme) ----------
   Anything theme-specific goes into that theme's own .css file. */
const FIXED = {
  accent: "#ffffff",     // accent color
  buttonRadius: "999px", // play buttons, filter chips, search, home: round
  panelRadius: "22px",   // corners of the sidebar, main view and right panel
  windowRadius: 12,      // window corners
  windowAlpha: 100,      // window opacity (%)
};

const PANELS = "html #Desktop_LeftSidebar_Id, html #main-view, html .Root > div > div:has(> .LayoutResizer__inline-start)";
const BUTTONS = 'html :is([data-encore-id="buttonPrimary"] > span, [data-testid="control-button-playpause"] > span, [data-encore-id="chip"] > span, [data-testid="home-button"], form[role="search"] input)';

function fixedCss() {
  return [
    `${BUTTONS} { border-radius: ${FIXED.buttonRadius} !important; }`,
    `${PANELS} { border-radius: ${FIXED.panelRadius} !important; }`,
    // Round and clip the panels' inner layers too; otherwise Spotify's own 8px corner shows inside like
    // a second panel. Leave the resize handles alone, they sit outside the edge.
    `html #Desktop_LeftSidebar_Id > :not(.LayoutResizer__resize-bar), html .Root > div > div:has(> .LayoutResizer__inline-start) > :not(.LayoutResizer__resize-bar), html #main-view > * { border-radius: ${FIXED.panelRadius} !important; overflow: hidden !important; }`,
    // Floating player: its grid row goes away and the panels reach the bottom of the window
    `html .Root > div:has(> div > [data-testid="now-playing-bar"]) { grid-template-rows: auto auto minmax(0, 1fr) 0 !important; padding-bottom: 0 !important; box-sizing: border-box !important; }`,
    `html .Root > div > div:has(> [data-testid="now-playing-bar"]) { position: absolute !important; left: 0; right: 0; bottom: 18px; height: auto !important; padding: 0 !important; z-index: 20; pointer-events: none; display: flex !important; justify-content: center; background: transparent !important; }`,
    `html [data-testid="now-playing-bar"] { pointer-events: auto; width: auto !important; min-width: 0 !important; }`,
    // Keep the floating player from covering the last rows: room under the scrolled content
    `html :is(#main-view, #Desktop_LeftSidebar_Id, .Root > div > div:has(> .LayoutResizer__inline-start)) [data-overlayscrollbars-viewport]:not([data-overlayscrollbars-viewport] [data-overlayscrollbars-viewport]) > div:first-child { padding-bottom: 96px !important; box-sizing: border-box; }`,
    // Cover art always in color
    `html :is(#main-view [data-encore-id="card"] img, #main-view [data-testid="shortcut-image"] img) { filter: none !important; }`,
    M.hasHost ? wholeCss() : "",
  ].join("\n");
}

/* ---------- Selections: theme + per-part designs ---------- */

const key = (g) => (g === "themes" ? "mod.theme" : `mod.${g}`);
M.group = (g) => M.groups.find((x) => x.id === g);
M.get = (g = "themes") => {
  const id = localStorage.getItem(key(g));
  return M.group(g)?.items.some((t) => t.id === id) ? id : (g === "themes" ? "akrilik" : "default");   // Acrylic on first run
};
M.set = (g, id) => {
  if (id === undefined) { id = g; g = "themes"; }   // old call form: M.set(themeId)
  localStorage.setItem(key(g), id); M.refresh();
};
M.getTheme = () => M.get("themes");      // for old callers
M.setTheme = (id) => M.set("themes", id);

M.refresh = () => {
  styleEl("mod-base").textContent = M.baseCss;
  const cur = M.get("themes");
  const item = M.group("themes")?.items.find((x) => x.id === cur);
  styleEl("mod-themes").textContent = item ? item.css : "";
  root.dataset.modTheme = cur;
  // fixed settings go on top of the theme
  styleEl("mod-fixed").textContent = fixedCss();
  // part designs go last, so they can override the fixed settings in their own area
  for (const g of M.groups) {
    if (g.id === "themes") continue;
    const sel = g.items.find((x) => x.id === M.get(g.id));
    styleEl(`mod-${g.id}`).textContent = sel ? sel.css : "";
    root.dataset[`mod${g.id[0].toUpperCase()}${g.id.slice(1)}`] = M.get(g.id);
  }
  root.style.setProperty("--mod-custom-accent", FIXED.accent);
  applyWindow();
  renderPanel();
  syncFeatures();
};

/* ---------- Top bar button ---------- */

const hasChoices = () => M.groups.some((g) => g.items.length > 1);
// the panel is worth showing when a part offers a choice, or when the widgets can be switched (needs the host)
const hasPanel = () => hasChoices() || !!M.hasHost;

/* ---------- Widgets (taskbar player, desktop widget), switched from the panel ---------- */
const WIDGETS = [
  ["taskbar", "Taskbar player", "Small player on the taskbar, next to the clock"],
  ["desktop", "Desktop widget", "A bigger player card on the desktop; drag it anywhere"],
];
const widgetPrefs = () => { try { return { taskbar: true, desktop: false, ...JSON.parse(localStorage.getItem("mod.widgets") || "{}") }; } catch { return { taskbar: true, desktop: false }; } };
function sendWidgets() { const w = widgetPrefs(); sendHost(`widgets ${JSON.stringify({ taskbar: !!w.taskbar, desktop: !!w.desktop })}`); }
function setWidget(k, on) { localStorage.setItem("mod.widgets", JSON.stringify({ ...widgetPrefs(), [k]: on })); sendWidgets(); renderPanel(); }

function ensureButton() {
  // nothing to choose (one design per part): no button, no panel
  if (!hasPanel()) { document.getElementById("mod-btn")?.remove(); return; }
  const ref = $('[data-testid="whats-new-feed-button"]') || $('[data-testid="friend-activity-button"]');
  let btn = document.getElementById("mod-btn");
  if (btn && btn.isConnected && !(btn.classList.contains("mod-floating") && ref)) return;
  btn?.remove();
  btn = document.createElement("button");
  btn.id = "mod-btn";
  btn.setAttribute("aria-label", "Appearance");
  btn.title = "Appearance (Ctrl+Alt+T)";
  btn.innerHTML = ICON;
  btn.addEventListener("click", (e) => { e.stopPropagation(); togglePanel(); });
  if (ref) { btn.className = ref.className; ref.parentElement.insertBefore(btn, ref); }
  else { btn.className = "mod-floating"; document.body.appendChild(btn); }
}

/* ---------- Panel: one tab per part that offers a choice ---------- */

const panelEl = () => document.getElementById("mod-panel");
let activeTab = "themes";

function card(g, t, cur) {
  const on = t.id === cur;
  const sw = t.swatch
    ? `<span class="mod-swatch">${t.swatch.map((c) => `<i style="background:${esc(c)}"></i>`).join("")}</span>`
    : "";
  return `<button class="mod-card${on ? " on" : ""}${t.swatch ? "" : " slim"}" data-g="${esc(g)}" data-id="${esc(t.id)}">
    ${sw}
    <span class="mod-name">${esc(t.name)}${on ? '<b class="mod-check">✓</b>' : ""}</span>
    <span class="mod-desc">${esc(t.desc)}</span>
  </button>`;
}

function renderPanel() {
  const p = panelEl();
  if (!p) return;
  const tabs = M.groups.filter((g) => g.items.length > 1);
  if (!tabs.some((g) => g.id === activeTab)) activeTab = tabs[0]?.id || "themes";
  const g = M.group(activeTab);
  const cur = M.get(activeTab);
  p.innerHTML = `
    <div class="mod-head">
      <div class="mod-title">Fumefy</div>
      <button class="mod-x" aria-label="Close">✕</button>
    </div>
    ${tabs.length > 1 ? `<div class="mod-tabs">${tabs.map((x) => `<button class="mod-tab${x.id === activeTab ? " on" : ""}" data-tab="${esc(x.id)}">${esc(x.title)}</button>`).join("")}</div>` : ""}
    ${tabs.length ? `<div class="mod-grid">${(g?.items || []).map((t) => card(activeTab, t, cur)).join("")}</div>` : ""}
    ${M.hasHost ? `<div class="mod-section">Widgets</div>
    <div class="mod-toggles">${WIDGETS.map(([k, name, desc]) => { const on = !!widgetPrefs()[k]; return `
      <button class="mod-toggle${on ? " on" : ""}" data-w="${k}" role="switch" aria-checked="${on}">
        <span class="mod-tt"><span class="mod-name">${esc(name)}</span><span class="mod-desc">${esc(desc)}</span></span>
        <span class="mod-switch" aria-hidden="true"></span>
      </button>`; }).join("")}</div>` : ""}
    <div class="mod-foot">Ctrl+Alt+T to open / close</div>`;
  p.querySelector(".mod-x").onclick = closePanel;
  p.querySelectorAll(".mod-tab").forEach((b) => (b.onclick = () => { activeTab = b.dataset.tab; renderPanel(); }));
  p.querySelectorAll(".mod-card").forEach((c) => (c.onclick = () => M.set(c.dataset.g, c.dataset.id)));
  p.querySelectorAll(".mod-toggle").forEach((t) => (t.onclick = () => setWidget(t.dataset.w, t.getAttribute("aria-checked") !== "true")));
}

/* ---------- Parts of the designs that need code ---------- */

// Friend panel: Spotify's list is hidden and our own list with album covers is drawn from the same data.
// Clicks are forwarded to the real links / buttons in Spotify's hidden list.
const FEED = { default: 1 };
const covers = (() => { try { return JSON.parse(localStorage.getItem("mod.covers") || "{}"); } catch { return {}; } })();
const coverAsked = new Set();
M.setCover = (id, url) => {
  covers[id] = url || "";
  const keys = Object.keys(covers);
  if (keys.length > 300) keys.slice(0, keys.length - 300).forEach((k) => delete covers[k]);
  try { localStorage.setItem("mod.covers", JSON.stringify(covers)); } catch {}
  syncFriendFeed();
};
function coverOf(trackId) {
  if (!trackId) return "";
  if (trackId in covers) return covers[trackId];
  if (window.modHost && !coverAsked.has(trackId)) { coverAsked.add(trackId); try { window.modHost("cover " + trackId); } catch {} }
  return "";
}
function friendRows() {
  const ul = $('#Desktop_PanelContainer_Id ul:has(> li figure ~ button)');
  if (!ul) return { ul: null, rows: [] };
  const rows = [...ul.children].filter((li) => li.querySelector("figure ~ button")).map((li) => {
    const info = li.querySelector(":scope > div > div:last-child");
    const a = (sel) => info?.querySelector(sel);
    const track = a('a[href*="/track/"]'), artist = a('a[href*="/artist/"]'), user = a('a[href*="/user/"]');
    const ctx = info?.querySelector(":scope > p:last-of-type a");
    const time = (info?.querySelector(":scope > div:first-child > p:last-child")?.textContent || "").trim();
    return {
      li,
      av: li.querySelector("figure img")?.src || "",
      name: (user?.textContent || "").trim(),
      song: (track?.textContent || "").trim(),
      artist: (artist?.textContent || "").trim(),
      ctx: (ctx?.textContent || "").trim(),
      time,
      on: !!info?.querySelector(":scope > div:first-child > p:last-child svg"),
      tid: (track?.getAttribute("href") || "").match(/track\/([A-Za-z0-9]{22})/)?.[1] || "",
    };
  });
  return { ul, rows };
}
function hueOf(s) { let h = 0; for (const c of s) h = (h * 31 + c.charCodeAt(0)) % 360; return h; }
function syncFriendFeed() {
  let box = document.getElementById("mod-fr");
  const v = M.get("friends");
  const { ul, rows } = friendRows();
  document.documentElement.classList.toggle("mod-feed", !!(FEED[v] && ul));
  if (!FEED[v] || !ul) { box?.remove(); return; }
  if (!box) {
    box = document.createElement("div"); box.id = "mod-fr"; box.lang = "en";
    box.addEventListener("click", onFeedClick);
  }
  if (box.nextElementSibling !== ul) ul.parentElement.insertBefore(box, ul);
  const data = rows.map((r) => ({ ...r, li: undefined, cover: coverOf(r.tid) }));
  const sig = v + JSON.stringify(data);
  if (box.dataset.sig === sig) return;
  box.dataset.sig = sig; box.dataset.v = v;
  // time groups: now / last hour (time given in minutes) / earlier. Spotify's own text, any language.
  const grp = (d) => (d.on ? 0 : /\b(dk|min|mins|minutes?)\b|dk\.|min\./i.test(d.time) ? 1 : 2);
  const LABELS = ["Now", "Last hour", "Earlier"];
  let last = -1;
  box.innerHTML = data.map((d, i) => {
    const g = grp(d);
    const head = g !== last ? `<div class="mf-label" data-g="${g}">${LABELS[g]}</div>` : "";
    last = g;
    const art = d.cover ? `<img class="mf-art" src="${esc(d.cover)}" alt="">` : `<div class="mf-art mf-noart" style="--h:${hueOf(d.song + d.artist)}"></div>`;
    return `${head}<div class="mf-item${d.on ? " on" : ""}${i === 0 ? " first" : ""}" data-i="${i}" data-g="${g}">
      <div class="mf-cover" data-act="play">${art}<div class="mf-vinyl"></div><span class="mf-playbtn" aria-hidden="true"><svg viewBox="0 0 16 16" width="14" height="14"><path d="M4 2.5v11l9.5-5.5z" fill="currentColor"/></svg></span></div>
      <img class="mf-av" data-act="user" src="${esc(d.av)}" alt="${esc(d.name)}" title="${esc(d.name)}">
      <div class="mf-text">
        <a class="mf-song" data-act="track" title="${esc(d.song)}">${esc(d.song)}</a>
        <span class="mf-artist"><a data-act="artist">${esc(d.artist)}</a></span>
        <span class="mf-meta"><a class="mf-who" data-act="user">${esc(d.name.split(" ")[0])}</a><span class="mf-time">${d.on ? '<span class="mf-eq"><i></i><i></i><i></i></span>' : esc(d.time)}</span></span>
      </div>
    </div>`;
  }).join("") || `<div class="mf-empty">When your friends listen to something, it shows up here.</div>`;
}
function onFeedClick(e) {
  const t = e.target.closest("[data-act]"), item = e.target.closest(".mf-item");
  if (!t || !item) return;
  const r = friendRows().rows[+item.dataset.i];
  if (!r) return;
  e.preventDefault();
  const q = { play: "figure ~ button", user: 'a[href*="/user/"]', track: 'a[href*="/track/"]', artist: 'a[href*="/artist/"]' }[t.dataset.act];
  r.li.querySelector(q)?.click();
}

// Library: while the library is expanded, Spotify's list is made invisible and our own view is drawn
// from the same items. A click opens the real row; the play button on a cover clicks the real play button.
function libRows() {
  const lib = $("#Desktop_LeftSidebar_Id");
  const grid = lib?.querySelector('[role="grid"]');
  if (!grid) return { lib, grid: null, rows: [] };
  const rows = [...grid.querySelectorAll('[role="row"]')].filter((r) => r.querySelector('[data-encore-id="listRow"]')).map((r) => {
    const sub = (r.querySelector('[data-encore-id="listRowSubtitle"]')?.textContent || "").trim();
    const type = sub.split("•")[0].trim();
    return {
      el: r,
      title: (r.querySelector('[data-encore-id="listRowTitle"]')?.textContent || "").trim(),
      sub, type,
      owner: sub.includes("•") ? sub.split("•").slice(1).join("•").trim() : "",
      img: r.querySelector('img[data-testid="entity-image"]')?.src || "",
      artist: /^(Sanatçı|Artist)$/i.test(type),
      pinned: !!r.querySelector('[data-encore-id="listRowSubtitle"] svg'),
    };
  });
  return { lib, grid, rows };
}
function syncLibraryView() {
  let box = document.getElementById("mod-lib");
  const { lib, grid, rows } = libRows();
  const wide = lib && lib.getBoundingClientRect().width > 160;
  const on = !!(grid && wide && rows.length);
  root.classList.toggle("mod-libview", on);
  if (!on) { box?.remove(); return; }
  if (!box) {
    box = document.createElement("div"); box.id = "mod-lib"; box.lang = "en";
    box.addEventListener("keydown", (e) => { if (e.key === "Enter" && e.target.matches("[data-i]")) e.target.click(); });
    box.addEventListener("click", (e) => {
      const it = e.target.closest("[data-i]");
      if (!it) return;
      const r = libRows().rows[+it.dataset.i];
      if (!r) return;
      if (e.target.closest("[data-play]")) r.el.querySelector('[data-testid="play-button"]')?.click();
      else r.el.querySelector('[role="button"]')?.click();
    });
  }
  if (box.nextElementSibling !== grid) grid.parentElement.insertBefore(box, grid);
  const sig = JSON.stringify(rows.map((r) => [r.title, r.sub, r.img, r.pinned]));
  if (box.dataset.sig === sig) return;
  box.dataset.sig = sig;
  const playSvg = '<svg viewBox="0 0 16 16" width="14" height="14" aria-hidden="true"><path d="M4 2.5v11l9.5-5.5z" fill="currentColor"/></svg>';
  const art = (r) => r.img ? `<img class="ml-img${r.artist ? " round" : ""}" src="${esc(r.img)}" alt="">` : `<div class="ml-img ml-noimg${r.artist ? " round" : ""}"></div>`;
  const item = (r, i, cls = "") => `<div class="ml-item ${cls}" data-i="${i}" role="button" tabindex="0" title="${esc(r.title)}">
      <div class="ml-cover">${art(r)}<span class="ml-play" data-play>${playSvg}</span></div>
      <div class="ml-text"><span class="ml-title">${esc(r.title)}</span><span class="ml-sub">${esc(r.sub)}</span></div>
    </div>`;
  const idx = (r) => rows.indexOf(r);
  // pinned items (or, if none, the three most recent) in big tiles on top, the rest as a list below
  const pinned = rows.filter((r) => r.pinned);
  const top = (pinned.length ? pinned : rows).slice(0, 3);
  const rest = rows.filter((r) => !top.includes(r));
  const html = `<div class="ml-top">${top.map((r) => item(r, idx(r), "big")).join("")}</div>` +
    (rest.length ? `<div class="ml-label">Recently opened</div>${rest.map((r) => item(r, idx(r))).join("")}` : "");
  box.innerHTML = html;
}

// Profile: this month's top artists orbit the profile picture (that shelf is not shown again below)
const PROFILE_SEC = 'section:has(> div > [data-testid="entity-header"] [data-testid="user-image"])';
function syncProfileOrbit() {
  const sec = $(`#main-view ${PROFILE_SEC}`);
  let orbit = document.getElementById("mod-orbit");
  const hdr = sec?.querySelector('[data-testid="entity-header"] > div:last-child');
  const shelf = sec?.querySelector('[data-testid="component-shelf"]');
  if (!hdr || !shelf) { orbit?.remove(); return; }
  if (shelf.dataset.modOrbitSrc !== "1") shelf.dataset.modOrbitSrc = "1";
  if (!orbit) {
    orbit = document.createElement("div"); orbit.id = "mod-orbit";
    orbit.addEventListener("click", (e) => {
      const b = e.target.closest("[data-i]"); if (!b) return;
      const card = $(`#main-view ${PROFILE_SEC} [data-testid="component-shelf"]`)?.querySelectorAll('[data-encore-id="card"]')[+b.dataset.i];
      (card?.querySelector("a[href]") || card)?.click();
    });
  }
  const img = hdr.querySelector('[data-testid="user-image"]')?.parentElement;
  if (img && orbit.parentElement !== img.parentElement) img.parentElement.insertBefore(orbit, img);
  const me = hdr.querySelector('[data-testid="user-image"] img')?.src || "";
  const cards = [...shelf.querySelectorAll('[data-encore-id="card"]')].slice(0, 8).map((c) => ({
    src: c.querySelector("img")?.currentSrc || c.querySelector("img")?.src || "",
    name: (c.querySelector('[data-encore-id="cardTitle"]')?.textContent || c.querySelector("p")?.textContent || "").trim(),
  }));
  const sig = me + JSON.stringify(cards);
  if (orbit.dataset.sig === sig) return;
  orbit.dataset.sig = sig;
  // each next artist is a bit smaller and further out
  const angles = [-22, 158, 23, 203, 113, 293, 68, 248];   // 45° apart, ranks alternate sides
  orbit.innerHTML = `<img class="mo-me" src="${esc(me)}" alt="">` + cards.map((c, i) => {
    const size = Math.round(86 - i * 6), dist = 128 + i * 9, a = (angles[i] * Math.PI) / 180;
    const x = Math.round(Math.cos(a) * dist * 1.45), y = Math.round(Math.sin(a) * dist * 0.78);
    return `<button class="mo-b" data-i="${i}" title="${esc(c.name)}" aria-label="${esc(c.name)}" style="--s:${size}px;--x:${x}px;--y:${y}px;--d:${i * 0.4}s">${c.src ? `<img src="${esc(c.src)}" alt="">` : ""}</button>`;
  }).join("");
}

// Settings: sticky section menu on the left; a click scrolls to that section and the current
// section is highlighted while scrolling
function settingsSections() {
  const page = $('#main-view [data-testid="settings-page"]');
  return { page, secs: page ? [...page.children].filter((c) => c.id !== "mod-setnav" && c.querySelector("h2")) : [] };
}
function syncSettingsNav() {
  let nav = document.getElementById("mod-setnav");
  const { page, secs } = settingsSections();
  if (!page || !secs.length) { nav?.remove(); return; }
  if (!nav) {
    nav = document.createElement("nav"); nav.id = "mod-setnav"; nav.setAttribute("aria-label", "Settings sections");
    nav.addEventListener("click", (e) => {
      const b = e.target.closest("[data-sec]"); if (!b) return;
      pinSettingsNav(+b.dataset.sec);
      settingsSections().secs[+b.dataset.sec]?.scrollIntoView({ behavior: "smooth", block: "start" });
    });
  }
  if (page.firstElementChild !== nav) page.insertBefore(nav, page.firstElementChild);
  // span exactly the sections' rows; extra implicit rows would add row gaps under the page
  const span = `1 / span ${Math.max(1, page.children.length - 1)}`;
  if (nav.style.gridRow !== span) nav.style.gridRow = span;
  const names = secs.map((s) => s.querySelector("h2").textContent.trim());
  const sig = names.join("|");
  if (nav.dataset.sig !== sig) {
    nav.dataset.sig = sig;
    nav.innerHTML = names.map((n, i) => `<button type="button" data-sec="${i}">${esc(n)}</button>`).join("");
  }
  markSettingsNav();
}
// A clicked section stays selected until the scroll ends and the user scrolls on their own
// (the last sections can't reach the top of the page, so the highlight used to fall back one).
let setNavPinned = -1, setNavSettled = -1, setNavSettleTimer = 0;
const setNavViewport = () => $('#main-view [data-overlayscrollbars-viewport]');
function markSettingsNav() {
  const nav = document.getElementById("mod-setnav");
  if (!nav) return;
  const { secs } = settingsSections();
  const v = setNavViewport();
  let cur = 0;
  if (setNavPinned >= 0) cur = setNavPinned;
  else if (v && v.scrollTop + v.clientHeight >= v.scrollHeight - 4) {
    cur = secs.length - 1;   // at the very bottom: the last section
  } else {
    // the last section whose heading passed the line under the top bar (same spot a click scrolls to)
    const line = (v?.getBoundingClientRect().top || 0) + 84 + 24;
    secs.forEach((s, i) => { if (s.getBoundingClientRect().top <= line) cur = i; });
  }
  nav.querySelectorAll("[data-sec]").forEach((btn) => {
    const on = +btn.dataset.sec === cur;
    btn.classList.toggle("on", on);
    if (on) btn.setAttribute("aria-current", "true"); else btn.removeAttribute("aria-current");
  });
}
function pinSettingsNav(i) {
  setNavPinned = i; setNavSettled = -1;
  markSettingsNav();
}
let setNavTimer = 0;
const onAnyScroll = () => {
  const v = setNavViewport();
  if (setNavPinned >= 0 && v) {
    if (setNavSettled < 0) {
      // the smooth scroll after a click is still running; note where it stops
      clearTimeout(setNavSettleTimer);
      setNavSettleTimer = setTimeout(() => { setNavSettled = setNavViewport()?.scrollTop ?? 0; }, 220);
    } else if (Math.abs(v.scrollTop - setNavSettled) > 24) {
      setNavPinned = -1;   // the user scrolled on their own
    }
  }
  if (!setNavTimer) setNavTimer = setTimeout(() => { setNavTimer = 0; markSettingsNav(); }, 60);
};
document.addEventListener("scroll", onAnyScroll, true);
cleanups.push(() => { document.removeEventListener("scroll", onAnyScroll, true); clearTimeout(setNavSettleTimer); });

// Home: a greeting for the time of day + a big "pick up where you left off" card with the current song
function syncHomeHero() {
  let hero = document.getElementById("mod-home-hero");
  const home = $('#main-view section[data-testid="home-page"]');
  // at the very top of the shelf column (above the shortcuts too)
  const col = home?.querySelector('[data-testid="component-shelf"]')?.parentElement;
  const anchor = col && [...col.children].find((c) => c.id !== 'mod-home-hero');
  if (!anchor) { hero?.remove(); return; }
  if (!hero) {
    hero = document.createElement("div"); hero.id = "mod-home-hero"; hero.lang = "en";
    hero.addEventListener("click", (e) => {
      const a = e.target.closest("[data-act]")?.dataset.act;
      if (a === "play") $('[data-testid="control-button-playpause"]')?.click();
      else if (a === "open") $('[data-testid="now-playing-widget-v2"] a[href]')?.click();
    });
  }
  if (anchor.previousElementSibling !== hero) anchor.parentElement.insertBefore(hero, anchor);
  const h = new Date().getHours();
  const hello = h < 5 ? "Good night" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : h < 22 ? "Good evening" : "Good night";
  const name = ($('[data-testid="user-widget-link"]')?.getAttribute("aria-label") || "").trim();
  const np = nowPlaying();
  const sig = [hello, name, np.title, np.artist, np.cover, np.playing].join("|");
  if (hero.dataset.sig === sig) return;
  hero.dataset.sig = sig;
  hero.innerHTML = `<h1 class="mh-hello">${esc(hello)}${name ? ", " + esc(name) : ""}</h1>` + (np.title ? `
    <div class="mh-card">
      <div class="mh-label">Pick up where you left off</div>
      <div class="mh-row">
        <img class="mh-cover" src="${esc(np.cover)}" alt="" data-act="open">
        <div class="mh-text"><a class="mh-title" data-act="open">${esc(np.title)}</a><span class="mh-artist">${esc(np.artist)}</span></div>
        <button class="mh-play" data-act="play" aria-label="${np.playing ? "Pause" : "Play"}">${np.playing
          ? '<svg viewBox="0 0 16 16" width="18" height="18"><path d="M4 2h3v12H4zM9 2h3v12H9z" fill="currentColor"/></svg>'
          : '<svg viewBox="0 0 16 16" width="18" height="18"><path d="M4 2.5v11l9.5-5.5z" fill="currentColor"/></svg>'}</button>
      </div>
    </div>` : "");
}

// What is playing right now (also sent to the taskbar mini player)
function nowPlaying() {
  const w = $('[data-testid="now-playing-widget-v2"]');
  const links = w ? [...w.querySelectorAll("a[href]")] : [];
  const title = (links.find((a) => /\/(track|album|playlist|episode)\//.test(a.getAttribute("href")))?.textContent || "").trim();
  const artist = links.filter((a) => /\/artist\//.test(a.getAttribute("href"))).map((a) => a.textContent.trim()).join(", ");
  // the player shows a 64px cover; ask Spotify's image CDN for the 300px version of the same image (sharp in the widgets)
  const cover = ($('[data-testid="now-playing-bar"] [data-testid="cover-art-image"]')?.src || "").replace(/ab67616d0000[0-9a-f]{4}/, "ab67616d00001e02");
  const playing = /duraklat|pause/i.test($('[data-testid="control-button-playpause"]')?.getAttribute("aria-label") || "");
  // the "add to Liked Songs" button next to the title; aria-checked="true" once the song is liked
  const liked = $('[data-testid="now-playing-widget-v2"] button[aria-checked]')?.getAttribute("aria-checked") === "true";
  return { title, artist, cover, playing, liked, progress: Math.round(progressPct()), volume: Math.round(volumePct()) };
}

// Volume (%), read from Spotify's own volume bar
function volumePct() {
  const el = $('[data-testid="volume-bar"] [data-testid="progress-bar"]');
  return el ? parseFloat(el.style.getPropertyValue("--progress-bar-transform")) || 0 : 0;
}
// Set the volume (0-100) through the hidden range input behind Spotify's volume bar
function setVolume(pct) {
  const inp = $('[data-testid="volume-bar"] input[type="range"]');
  if (!inp) return;
  const step = inp.step;
  inp.step = "any";   // the input rounds to 0.1 steps otherwise
  Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, "value").set.call(inp, String(Math.max(0, Math.min(100, pct)) / 100));
  inp.dispatchEvent(new Event("input", { bubbles: true }));
  inp.dispatchEvent(new Event("change", { bubbles: true }));
  inp.step = step;
}

// Player: song progress (%), read from the variable on Spotify's own progress bar
function progressPct() {
  const el = $('[data-testid="playback-progressbar"] [data-testid="progress-bar"]');
  return el ? parseFloat(el.style.getPropertyValue("--progress-bar-transform")) || 0 : 0;
}

// Player: progress ring around the play button
function syncRing() {
  let r = document.getElementById("mod-ring");
  const btn = $('[data-testid="control-button-playpause"]');
  if (!btn) { r?.remove(); return; }
  if (!r || r.parentElement !== btn) {
    r?.remove();
    btn.insertAdjacentHTML("beforeend", `<svg id="mod-ring" viewBox="0 0 58 58" aria-hidden="true"><circle class="bg" cx="29" cy="29" r="26"/><circle class="fg" cx="29" cy="29" r="26" transform="rotate(-90 29 29)"/></svg>`);
    r = document.getElementById("mod-ring");
  }
  const C = 2 * Math.PI * 26, fg = r.querySelector(".fg");
  fg.style.strokeDasharray = String(C);
  fg.style.strokeDashoffset = String(C * (1 - progressPct() / 100));
}

// Device pill ("Playing on ..."): opens right next to the "Connect to a device" button
let lastPill = null;
function placeConnectPill() {
  const bar = document.querySelector('[data-testid="now-playing-bar"]');
  const btns = bar && bar.querySelector(':scope > div:first-child > div:last-child > div');
  const dev = btns && [...btns.children].find((c) => c.tagName === 'SPAN');
  if (!dev) return;
  const pill = bar.querySelector(':scope > div:nth-child(2):not(#mod-pill-ghost)');
  const set = (k, v) => { if (bar.style.getPropertyValue(k) !== v) bar.style.setProperty(k, v); };
  if (!pill) {
    // the pill went away: play the closing animation on a copy of its last state
    if (lastPill && !document.getElementById('mod-pill-ghost')) {
      const g = lastPill; g.id = 'mod-pill-ghost'; g.setAttribute('aria-hidden', 'true'); g.inert = true; bar.appendChild(g);
      setTimeout(() => g.remove(), 320);
    }
    lastPill = null; set('--mod-pill-w', '0px'); return;
  }
  document.getElementById('mod-pill-ghost')?.remove();
  lastPill = pill.cloneNode(true);
  set('--mod-pill-w', pill.offsetWidth + 12 + 'px');
  set('--mod-pill-x', Math.round(dev.getBoundingClientRect().right - bar.getBoundingClientRect().left + 6) + 'px');
}
// Taskbar mini player: send the current song to the host whenever it changes (tray.ps1 shows it)
let lastNp = "";
function sendNowPlaying() {
  if (!M.hasHost) return;
  const np = nowPlaying();
  const line = `np ${JSON.stringify(np)}`;
  if (line === lastNp) return;
  lastNp = line;
  sendHost(line);
}
// Commands coming back from the taskbar mini player
M.control = (cmd) => {
  const vol = /^vol (\d{1,3})$/.exec(cmd);
  if (vol) { setVolume(+vol[1]); return; }
  if (cmd === "volup" || cmd === "voldown") { setVolume(volumePct() + (cmd === "volup" ? 5 : -5)); return; }
  const sel = {
    prev: '[data-testid="control-button-skip-back"]', play: '[data-testid="control-button-playpause"]',
    next: '[data-testid="control-button-skip-forward"]', mute: '[data-testid="volume-bar-toggle-mute-button"]',
    like: '[data-testid="now-playing-widget-v2"] button[aria-checked]',
  }[cmd];
  if (sel) $(sel)?.click();
};
function syncFeatures() {
  try { syncFriendFeed(); syncHomeHero(); syncLibraryView(); syncProfileOrbit(); syncSettingsNav(); syncRing(); } catch (e) { console.error("[fumefy] feature", e); }
}
const featureTimer = setInterval(() => { try { syncRing(); placeConnectPill(); syncHomeHero(); sendNowPlaying(); } catch {} }, 500);
cleanups.push(() => clearInterval(featureTimer));

function placePanel() {
  const p = panelEl(), b = document.getElementById("mod-btn");
  if (!p || !b) return;
  const r = b.getBoundingClientRect();
  p.style.top = `${Math.round(r.bottom + 8)}px`;
  p.style.right = `${Math.max(8, Math.round(innerWidth - r.right - 8))}px`;
}

function openPanel() {
  if (panelEl() || !hasPanel()) return;
  const p = document.createElement("div");
  p.id = "mod-panel";
  p.lang = "en";   // English upper-casing (WIDGETS, not WİDGETS)
  p.addEventListener("click", (e) => e.stopPropagation());
  document.body.appendChild(p);
  renderPanel();
  placePanel();
}
function closePanel() { panelEl()?.remove(); }
function togglePanel() { panelEl() ? closePanel() : openPanel(); }
M.openPanel = openPanel; M.closePanel = closePanel;

/* ---------- Window (needs inject.mjs --host) ----------
   The window is always one piece: Spotify's own window buttons and "•••" menu live in the strip at the
   very top. We cut that strip off end to end and move the page down by the same amount. Our own
   minimize / maximize / close buttons sit at the top right. */

const sendHost = (cmd) => { try { window.modHost && window.modHost(cmd); } catch {} };
// Spotify's own close/maximize/minimize buttons sit ~6-64px from the top (measured with WM_NCHITTEST)
const WHOLE_CUT = 66;
let sentWin = "";
function applyWindow(force) {
  if (!M.hasHost) return;
  const dpr = devicePixelRatio || 1;
  const key = `${FIXED.windowAlpha}|${FIXED.windowRadius}|${dpr}`;
  if (key === sentWin && !force) return;
  sentWin = key;
  sendHost(`alpha ${FIXED.windowAlpha}`);
  // the helper builds the shape from the window size; when maximized it moves the window up by the strip
  sendHost(`whole ${Math.round(WHOLE_CUT * dpr)} ${Math.round(FIXED.windowRadius * dpr)}`);
}
M.hostReady = () => {
  M.hasHost = true; sentWin = ""; lastNp = "";
  root.classList.add("mod-whole");
  M.refresh();            // also adds the CSS that moves the page down by the strip
  applyWindow(true); ensureLights(); ensureButton(); sendWidgets();
};

function wholeCss() {
  return `
html.mod-whole .Root { padding-top: ${WHOLE_CUT}px !important; box-sizing: border-box !important; }
/* empty placeholders Spotify keeps for its own buttons: hide them so the buttons reach the edges */
html.mod-whole #global-nav-bar div:has(> div > [data-testid="top-bar-back-button"]) > div:empty,
html.mod-whole #global-nav-bar div:has(> div > [data-testid="user-widget-link"]) > div:empty { display: none !important; }
html.mod-whole #global-nav-bar div:has(> div > [data-testid="user-widget-link"]) { padding-right: 12px !important; }
/* the window drag area moves down under the cut strip, onto the top bar */
html.mod-whole .body-drag-top { top: ${WHOLE_CUT}px !important; }
`;
}

/* ---------- Tooltips of the top bar ----------
   Spotify opens these above the button, which is inside the cut-off strip, so they were invisible.
   Move any tooltip that lands there to just below its button, and keep it inside the window. */
function fixTooltip(tip) {
  tip.style.translate = "";
  const r = tip.getBoundingClientRect();
  if (!r.height) return;
  let dx = 0, dy = 0;
  if (M.hasHost && r.top < WHOLE_CUT + 4) {
    // the button sits right under the tooltip; put the tooltip the same distance under the button
    const btn = document.elementFromPoint(Math.min(innerWidth - 2, Math.max(2, r.left + r.width / 2)), r.bottom + 14)?.closest("button, a, [role=button]");
    const b = btn?.getBoundingClientRect();
    const below = b ? b.bottom + 8 : WHOLE_CUT + 64;
    dy = below - r.top;
  }
  if (r.right + dx > innerWidth - 8) dx = innerWidth - 8 - r.right;
  if (r.left + dx < 8) dx = 8 - r.left;
  if (dx || dy) tip.style.translate = `${Math.round(dx)}px ${Math.round(dy)}px`;
}
// Spotify inserts and moves tooltips on its own schedule, so check the visible ones often (cheap: usually 0-1)
const fixTips = () => document.querySelectorAll("[data-tippy-root]").forEach((t) => {
  const r = t.getBoundingClientRect();
  if (!r.height) return;
  const off = (M.hasHost && r.top < WHOLE_CUT + 4) || r.right > innerWidth - 8 || r.left < 8;
  if (off || (t.style.translate && t.dataset.modTipAt !== String(Math.round(r.top)))) { fixTooltip(t); t.dataset.modTipAt = String(Math.round(t.getBoundingClientRect().top)); }
});
const tipMo = new MutationObserver(() => setTimeout(fixTips, 0));
tipMo.observe(document.body, { childList: true });
const tipTimer = setInterval(fixTips, 120);
cleanups.push(() => { tipMo.disconnect(); clearInterval(tipTimer); });

/* ---------- While resizing: frosted glass + window size in the middle ---------- */
let sizeHideTimer = 0;
function showSizeOverlay() {
  if (!M.hasHost) return;
  let o = document.getElementById("mod-size-overlay");
  if (!o) {
    o = document.createElement("div");
    o.id = "mod-size-overlay";
    o.innerHTML = `<div class="mod-size-box"><b></b><span>Window size</span></div>`;
    document.body.appendChild(o);
  }
  const dpr = devicePixelRatio || 1;
  o.querySelector("b").textContent = `${Math.round(innerWidth * dpr)} × ${Math.round((innerHeight - WHOLE_CUT) * dpr)}`;
  o.classList.add("on");
  clearTimeout(sizeHideTimer);
  sizeHideTimer = setTimeout(() => o.classList.remove("on"), 350);   // fades once resizing stops
}

// The top edge and top corners were cut off together with Spotify's buttons, so Windows' resize areas
// there are gone too. We put invisible grab areas on the visible top edge; while held, the helper
// resizes the window from that edge.
const RESIZERS = [["top", 12], ["tl", 13], ["tr", 14]];
function ensureResizers() {
  for (const [name, hit] of RESIZERS) {
    const id = `mod-resize-${name}`;
    let el = document.getElementById(id);
    if (!M.hasHost) { el?.remove(); continue; }
    if (el && el.isConnected) continue;
    el = document.createElement("div");
    el.id = id; el.className = "mod-resizer";
    el.addEventListener("mousedown", (e) => {
      if (e.button !== 0) return;
      e.preventDefault(); e.stopPropagation();
      showSizeOverlay();
      sendHost(`size ${hit}`);
    });
    document.body.appendChild(el);
  }
  root.style.setProperty("--mod-cut", `${WHOLE_CUT}px`);
}

// top right, in Windows order: minimize, maximize, close (close in the corner)
const LIGHTS = [
  ["min", "Minimize", '<path d="M2.5 6h7"/>'],
  ["max", "Maximize", '<path d="M3.5 8.5v-5h5M8.5 3.5v5h-5"/>'],
  ["close", "Close", '<path d="M3 3l6 6M9 3l-6 6"/>'],
];

function ensureLights() {
  ensureResizers();
  let box = document.getElementById("mod-lights");
  // top right corner: right after the profile button, last in the row
  const host = $('[data-testid="user-widget-link"]')?.parentElement;
  if (!M.hasHost || !host) { box?.remove(); root.classList.remove("mod-mac"); return; }
  root.classList.add("mod-mac");
  if (box && box.isConnected && box.parentElement === host && !box.nextElementSibling) return;
  box?.remove();
  box = document.createElement("div");
  box.id = "mod-lights";
  // a grip to move the window (double click: maximize), then the buttons
  box.innerHTML = `<span class="mod-grip" title="Move window (double click: maximize)"><svg viewBox="0 0 10 16" width="8" height="13" fill="currentColor"><circle cx="2" cy="2" r="1.4"/><circle cx="8" cy="2" r="1.4"/><circle cx="2" cy="8" r="1.4"/><circle cx="8" cy="8" r="1.4"/><circle cx="2" cy="14" r="1.4"/><circle cx="8" cy="14" r="1.4"/></svg></span>`;
  box.innerHTML += LIGHTS.map(([c, t, path]) =>
    `<button class="mod-light ${c}" data-c="${c}" aria-label="${t}" title="${t}"><svg viewBox="0 0 12 12" width="8" height="8" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round">${path}</svg></button>`).join("");
  box.querySelectorAll("button").forEach((b) => (b.onclick = (e) => { e.stopPropagation(); sendHost(b.dataset.c); }));
  const grip = box.querySelector(".mod-grip");
  grip.onmousedown = (e) => { if (e.button === 0 && e.detail === 1) { e.preventDefault(); sendHost("drag"); } };
  grip.ondblclick = (e) => { e.preventDefault(); sendHost("max"); };
  host.appendChild(box);
}

/* ---------- Events ---------- */

const onDocClick = () => closePanel();
const onKey = (e) => {
  if (e.key === "Escape") closePanel();
  if (e.ctrlKey && e.altKey && e.key.toLowerCase() === "t") { e.preventDefault(); togglePanel(); }
};
document.addEventListener("click", onDocClick);
document.addEventListener("keydown", onKey);
addEventListener("resize", placePanel);
cleanups.push(() => {
  document.removeEventListener("click", onDocClick);
  document.removeEventListener("keydown", onKey);
  removeEventListener("resize", placePanel);
});

// setTimeout, not requestAnimationFrame: Chromium stops animation frames while the window is
// behind another window, and these checks never ran then.
let moTimer = 0;
const mo = new MutationObserver(() => {
  if (moTimer) return;
  moTimer = setTimeout(() => { moTimer = 0; ensureButton(); ensureLights(); syncFriendFeed(); syncHomeHero(); syncLibraryView(); syncProfileOrbit(); syncSettingsNav(); try { placeConnectPill(); } catch {} }, 60);
});
mo.observe(document.body, { childList: true, subtree: true });
// recompute the strip if the display scale changes (moved to another monitor); show the overlay while resizing
const onResize = () => { applyWindow(); showSizeOverlay(); };
addEventListener("resize", onResize);
cleanups.push(() => { mo.disconnect(); removeEventListener("resize", onResize); });

// Fully remove the old version when the mod is updated
M.destroy = () => {
  cleanups.forEach((f) => f());
  closePanel();
  document.getElementById("mod-btn")?.remove();
  document.getElementById("mod-lights")?.remove();
  document.querySelectorAll(".mod-resizer, #mod-size-overlay, #mod-wave, #mod-ring, #mod-pill-ghost, #mod-fr, #mod-home-hero, #mod-lib, #mod-orbit, #mod-setnav").forEach((e) => e.remove());
  { const npb = document.querySelector('[data-testid="now-playing-bar"]'); npb?.style.removeProperty('--mod-pill-w'); npb?.style.removeProperty('--mod-pill-x'); }
  document.documentElement.classList.remove("mod-feed", "mod-libview"); document.querySelectorAll("[data-mod-orbit-src]").forEach((e) => e.removeAttribute("data-mod-orbit-src"));
  root.style.removeProperty("--mod-cover-color");
  root.classList.remove("mod-mac", "mod-whole");
  root.style.removeProperty("--mod-custom-accent");
  document.querySelectorAll('style[id^="mod-"]').forEach((s) => s.remove());
};

ensureButton();
M.refresh();
if (window.modHost) M.hostReady(); // the helper is already connected (page was reloaded)
console.log("[fumefy] loaded");
