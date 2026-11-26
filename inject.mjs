// Injects the Fumefy theme mod into a running Spotify (Chrome DevTools Protocol).
// Usage:  node inject.mjs            -> inject once
//         node inject.mjs --watch    -> watch theme/ and live-reload on every save
//         node inject.mjs --host     -> stay running: window shape, window buttons and the taskbar player work
//         (both flags can be combined)
import { readFileSync, readdirSync, existsSync, watch } from "node:fs";
import { join, dirname, basename } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";
import { createInterface } from "node:readline";

const DIR = dirname(fileURLToPath(import.meta.url));
const THEME_DIR = join(DIR, "theme");
const PORT = 9222;
const WATCH = process.argv.includes("--watch");
const HOST = process.argv.includes("--host"); // stays running for the window features
const NO_TRAY = process.argv.includes("--no-tray");
const KEEP = WATCH || HOST;

// Parts of the UI; each one is made of the .css files in theme/<folder>.
const GROUPS = [
  { id: "themes", title: "Theme" },
  { id: "friends", title: "Friend panel" },
  { id: "search", title: "Search" },
  { id: "player", title: "Player" },
  { id: "library", title: "Library" },
  { id: "home", title: "Home" },
  { id: "playlist", title: "Playlist" },
  { id: "artist", title: "Artist" },
  { id: "profile", title: "Profile" },
];

const read = (p) => (existsSync(p) ? readFileSync(p, "utf8") : "");
const hash = (s) => { let h = 0; for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0; return String(h); };

// The first comment of each file is its metadata:
// /* name: Glass | desc: ... | swatch: #111, #222, #333 | order: 1 | schemes: Pink=#ff2bd6, Blue=#3db5ff */
// schemes: color schemes, the first one is the default. The chosen scheme's color becomes the accent;
// the theme file can add scheme-specific colors with html[data-mod-scheme="blue"] { ... }.
const slug = (s) => s.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/\u0131/g, "i").replace(/[^a-z0-9]+/g, "-");
const parseSchemes = (s) => s ? s.split(",").map((p) => { const [n, c] = p.split("=").map((x) => x.trim()); return { id: slug(n), name: n, color: c }; }) : null;
function loadGroup(dir) {
  if (!existsSync(dir)) return [];
  return readdirSync(dir)
    .filter((f) => f.endsWith(".css"))
    .map((f) => {
      const css = read(join(dir, f));
      const meta = {};
      const m = css.match(/^\s*\/\*([\s\S]*?)\*\//);
      if (m) for (const part of m[1].split("|")) {
        const i = part.indexOf(":");
        if (i > 0) meta[part.slice(0, i).trim()] = part.slice(i + 1).trim();
      }
      return {
        id: basename(f, ".css"),
        name: meta.name || basename(f, ".css"),
        desc: meta.desc || "",
        swatch: meta.swatch ? meta.swatch.split(",").map((s) => s.trim()) : null,
        order: Number(meta.order ?? 99),
        schemes: parseSchemes(meta.schemes),
        // window: alpha=85 radius=14 -> applied to the window when this theme is chosen
        window: meta.window ? Object.fromEntries(meta.window.split(/\s+/).map((p) => p.split("=")).filter((p) => p.length === 2).map(([k, v]) => [k, +v])) : null,
        css,
      };
    })
    .sort((a, b) => a.order - b.order);
}
const loadGroups = () => GROUPS.map((g) => ({ ...g, items: loadGroup(join(THEME_DIR, g.id)) }));

function buildPayload() {
  const js = read(join(THEME_DIR, "mod.js"));
  const data = { groups: loadGroups(), baseCss: read(join(THEME_DIR, "mod.css")), jsHash: hash(js) };
  return `(() => {
    const data = ${JSON.stringify(data)};
    const run = () => {
      const old = window.__MOD;
      // if mod.js changed, tear the old version down and run the new one
      if (old && old.jsHash !== data.jsHash) { try { old.destroy && old.destroy(); } catch (e) {} window.__MOD = undefined; }
      window.__MOD = Object.assign(window.__MOD || {}, data);
      if (window.__MOD.refresh) { window.__MOD.refresh(); return; }
      try { (function(){\n${js}\n})(); } catch (e) { console.error("[fumefy] mod.js error", e); }
    };
    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", run);
    else run();
  })()`;
}

async function findTarget() {
  for (let i = 0; i < 30; i++) {
    try {
      const list = await (await fetch(`http://127.0.0.1:${PORT}/json`)).json();
      const t = list.find((x) => x.type === "page" && x.url.includes("xpui"));
      if (t) return t;
    } catch {}
    await new Promise((r) => setTimeout(r, 1000));
  }
  throw new Error("Spotify not found. Start it with start.ps1 first.");
}

const target = await findTarget();
const ws = new WebSocket(target.webSocketDebuggerUrl);
let id = 0;
const pending = new Map();
const send = (method, params = {}) =>
  new Promise((res) => {
    const i = ++id;
    pending.set(i, res);
    ws.send(JSON.stringify({ id: i, method, params }));
  });
let onEvent = () => {};
ws.onmessage = (e) => {
  const m = JSON.parse(e.data);
  if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id); }
  else if (m.method) onEvent(m);
};
await new Promise((r, j) => { ws.onopen = r; ws.onerror = () => j(new Error("Could not connect to Spotify (DevTools port)")); });

// --host: start the window helper and the taskbar player, forward commands from the page to them
if (HOST) {
  const ps = (file, stdio) => spawn("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-STA", "-File", join(DIR, file)], { stdio, windowsHide: true });
  const helper = ps("window.ps1", ["pipe", "inherit", "inherit"]);
  // islands: up to 12 islands, each "x,y,w,h,r" integers
  const ALLOWED = /^(round \d{1,2}|alpha \d{2,3}|islands( -?\d{1,5},-?\d{1,5},\d{1,5},\d{1,5},\d{1,4}){0,12}|whole( \d{1,3} \d{1,3})?|size 1[234]|min|max|close|drag)$/;

  // Taskbar mini player: gets the current song, sends prev / play / next back
  let tray = null;
  if (!NO_TRAY && existsSync(join(DIR, "tray.ps1"))) {
    tray = ps("tray.ps1", ["pipe", "pipe", "inherit"]);
    createInterface({ input: tray.stdout }).on("line", (line) => {
      const c = /^cmd (prev|play|next|show|volup|voldown|mute|like|vol \d{1,3})$/.exec(line.trim());
      if (!c) return;
      if (c[1] === "show") helper.stdin.write("show\n");
      else send("Runtime.evaluate", { expression: `window.__MOD && __MOD.control && __MOD.control(${JSON.stringify(c[1])})` });
    });
    tray.on("error", () => { tray = null; });
  }

  // "cover <track id>": fetch the album cover of a track in the friend panel from Spotify's public
  // oEmbed endpoint (the page itself can't make outside requests), check the URL and hand it back
  const coverBusy = new Set();
  const COVER_URL = /^https:\/\/[a-z0-9.-]+\.(scdn\.co|spotifycdn\.com)\/[A-Za-z0-9/._-]+$/;
  async function fetchCover(trackId) {
    if (coverBusy.has(trackId)) return;
    coverBusy.add(trackId);
    let url = "";
    try {
      const r = await fetch(`https://open.spotify.com/oembed?url=https://open.spotify.com/track/${trackId}`, { signal: AbortSignal.timeout(8000) });
      if (r.ok) { const j = await r.json(); if (COVER_URL.test(j.thumbnail_url || "")) url = j.thumbnail_url; }
    } catch {}
    coverBusy.delete(trackId);
    await send("Runtime.evaluate", { expression: `window.__MOD && __MOD.setCover && __MOD.setCover(${JSON.stringify(trackId)}, ${JSON.stringify(url)})` });
  }
  onEvent = (m) => {
    if (m.method !== "Runtime.bindingCalled" || m.params.name !== "modHost") return;
    const p = m.params.payload;
    const c = /^cover ([A-Za-z0-9]{22})$/.exec(p);
    if (c) { fetchCover(c[1]); return; }
    if (p.startsWith("widgets ")) {
      // which widgets are switched on -> taskbar player process
      try { const w = JSON.parse(p.slice(8)); tray?.stdin.write("cfg " + JSON.stringify({ taskbar: !!w.taskbar, desktop: !!w.desktop }) + "\n"); } catch {}
      return;
    }
    if (p.startsWith("np ")) {
      // now playing -> taskbar player (only a small, checked object is passed on)
      try {
        const np = JSON.parse(p.slice(3));
        const clean = {
          title: String(np.title || "").slice(0, 200), artist: String(np.artist || "").slice(0, 200),
          cover: COVER_URL.test(np.cover || "") ? np.cover : "", playing: !!np.playing, liked: !!np.liked,
          progress: Math.max(0, Math.min(100, Number(np.progress) || 0)),
          volume: Math.max(0, Math.min(100, Number(np.volume) || 0)),
        };
        tray?.stdin.write("np " + JSON.stringify(clean) + "\n");
      } catch {}
      return;
    }
    if (ALLOWED.test(p)) helper.stdin.write(p + "\n");
  };
  process.on("exit", () => { try { helper.stdin.write("quit\n"); } catch {} try { tray?.stdin.write("quit\n"); } catch {} });
  await send("Runtime.enable");
  await send("Runtime.addBinding", { name: "modHost" });
}

let scriptId = null;
async function inject() {
  const payload = buildPayload();
  const r = await send("Runtime.evaluate", { expression: payload });
  if (r.error || r.result?.exceptionDetails) console.error("Error:", JSON.stringify(r.error || r.result.exceptionDetails));
  if (HOST) await send("Runtime.evaluate", { expression: "window.__MOD && __MOD.hostReady && __MOD.hostReady()" });
  if (KEEP) {
    if (scriptId) await send("Page.removeScriptToEvaluateOnNewDocument", { identifier: scriptId });
    const a = await send("Page.addScriptToEvaluateOnNewDocument", { source: payload });
    scriptId = a.result?.identifier;
  }
  console.log(`[${new Date().toLocaleTimeString()}] Fumefy loaded (${loadGroups().map((g) => g.items.length + " " + g.title).join(", ")})`);
}

await inject();

if (KEEP) {
  if (WATCH) {
    console.log("Watching theme/ ... (Ctrl+C to quit)");
    let t;
    watch(THEME_DIR, { recursive: true }, () => {
      clearTimeout(t);
      t = setTimeout(() => inject().catch(console.error), 150);
    });
  }
  ws.onclose = () => { console.log("Spotify closed."); process.exit(0); };
} else {
  ws.close();
}
