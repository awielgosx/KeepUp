"use strict";

// ---------------------------------------------------------------------------
// Storage
// ---------------------------------------------------------------------------

const LS = {
  items: "keepup.items",
  dirty: "keepup.dirty",
  settings: "keepup.settings",
};

function load(key, fallback) {
  try {
    const raw = localStorage.getItem(key);
    return raw ? JSON.parse(raw) : fallback;
  } catch {
    return fallback;
  }
}
function save(key, value) {
  try { localStorage.setItem(key, JSON.stringify(value)); } catch {}
}

let items = load(LS.items, []);
let dirty = new Set(load(LS.dirty, []));
let settings = Object.assign(
  { claudeKey: "", supaUrl: "", supaAnon: "", syncKey: "", theme: "auto" },
  load(LS.settings, {})
);
let showDone = false;

function persist() {
  save(LS.items, items);
  save(LS.dirty, [...dirty]);
}

function newId() {
  return crypto.randomUUID ? crypto.randomUUID()
    : "10000000-1000-4000-8000-100000000000".replace(/[018]/g, c =>
        (c ^ (crypto.getRandomValues(new Uint8Array(1))[0] & (15 >> (c / 4)))).toString(16));
}

function blankItem() {
  return {
    id: newId(), title: "", due: null, all_day: false, place: "", course: "",
    kind: "todo", notes: "", done: false, deleted: false,
    updated_at: new Date().toISOString(),
  };
}

function upsertLocal(item) {
  item.updated_at = new Date().toISOString();
  const i = items.findIndex(x => x.id === item.id);
  if (i >= 0) items[i] = item; else items.push(item);
  dirty.add(item.id);
  persist();
  render();
  scheduleSync(800);
}

// ---------------------------------------------------------------------------
// Dates
// ---------------------------------------------------------------------------

const DAY = 86400000;
function startOfDay(d) { const x = new Date(d); x.setHours(0, 0, 0, 0); return x; }
function pad(n) { return String(n).padStart(2, "0"); }
function hhmm(d) { return `${pad(d.getHours())}:${pad(d.getMinutes())}`; }
function ymd(d) { return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`; }

/** Builds a due Date from local "YYYY-MM-DD" + optional "HH:MM". All-day
 *  items are stored at 23:59 local so they sort after timed items that day. */
function makeDue(dateStr, timeStr) {
  if (!dateStr) return { due: null, all_day: false };
  const [y, m, d] = dateStr.split("-").map(Number);
  if (timeStr) {
    const [hh, mm] = timeStr.split(":").map(Number);
    return { due: new Date(y, m - 1, d, hh, mm).toISOString(), all_day: false };
  }
  return { due: new Date(y, m - 1, d, 23, 59).toISOString(), all_day: true };
}

function dueLabel(item, now = new Date()) {
  if (!item.due) return { text: "", cls: "" };
  const d = new Date(item.due);
  const days = Math.round((startOfDay(d) - startOfDay(now)) / DAY);
  const time = item.all_day ? "" : " " + hhmm(d);
  const overdue = !item.done && d < now;
  let text;
  if (days === 0) text = "Today" + time;
  else if (days === 1) text = "Tomorrow" + time;
  else if (days === -1) text = "Yesterday" + time;
  else if (days > 1 && days < 7) text = d.toLocaleDateString("en-GB", { weekday: "short" }) + time;
  else text = d.toLocaleDateString("en-GB", { day: "numeric", month: "short" }) + time;
  return { text, cls: overdue ? "overdue" : days === 0 ? "today" : "" };
}

function bucketOf(item, now = new Date()) {
  if (!item.due) return "No date";
  const d = new Date(item.due);
  if (d < now) return "Overdue";
  const days = Math.round((startOfDay(d) - startOfDay(now)) / DAY);
  if (days === 0) return "Today";
  if (days === 1) return "Tomorrow";
  if (days < 7) return "This week";
  return "Later";
}
const BUCKETS = ["Overdue", "Today", "Tomorrow", "This week", "Later", "No date"];

// ---------------------------------------------------------------------------
// Rendering
// ---------------------------------------------------------------------------

const $ = sel => document.querySelector(sel);
const el = (tag, attrs = {}, ...kids) => {
  const n = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === "class") n.className = v;
    else if (k.startsWith("on")) n.addEventListener(k.slice(2), v);
    else n.setAttribute(k, v);
  }
  for (const k of kids) if (k != null) n.append(k);
  return n;
};

function byDue(a, b) {
  if (!a.due && !b.due) return a.updated_at < b.updated_at ? 1 : -1;
  if (!a.due) return 1;
  if (!b.due) return -1;
  return new Date(a.due) - new Date(b.due);
}

function rowFor(item) {
  const label = dueLabel(item);
  return el("div", { class: "row" + (item.done ? " done" : ""), onclick: () => openDetail(item) },
    el("button", {
      class: "check", "aria-label": item.done ? "Mark not done" : "Mark done",
      onclick: e => { e.stopPropagation(); toggleDone(item); },
    }),
    el("span", { class: "title" }, item.title || "Untitled"),
    el("span", { class: "due " + label.cls }, label.text),
  );
}

function render() {
  const list = $("#list");
  list.replaceChildren();
  const live = items.filter(i => !i.deleted);
  const open = live.filter(i => !i.done).sort(byDue);
  const done = live.filter(i => i.done).sort((a, b) => (a.updated_at < b.updated_at ? 1 : -1));

  if (!open.length) {
    list.append(el("div", { class: "empty" }, "Nothing on your plate.", el("br"),
      "Type below to add something."));
  }
  const now = new Date();
  for (const b of BUCKETS) {
    const group = open.filter(i => bucketOf(i, now) === b);
    if (!group.length) continue;
    list.append(el("div", { class: "group-label" + (b === "Overdue" ? " overdue" : "") }, b));
    group.forEach(i => list.append(rowFor(i)));
  }
  if (done.length) {
    list.append(el("button", { class: "done-toggle", onclick: () => { showDone = !showDone; render(); } },
      (showDone ? "Hide" : "Show") + ` done (${done.length})`));
    if (showDone) done.slice(0, 30).forEach(i => list.append(rowFor(i)));
  }

  const courses = [...new Set(live.map(i => i.course).filter(Boolean))].sort();
  $("#courses").replaceChildren(...courses.map(c => el("option", { value: c })));
}

function toggleDone(item) {
  upsertLocal({ ...item, done: !item.done });
  if (!item.done) toast("Done ✓", () => upsertLocal({ ...item, done: false }));
}

let toastTimer;
function toast(msg, undo) {
  document.querySelector(".toast")?.remove();
  const t = el("div", { class: "toast" }, msg);
  if (undo) t.append(el("button", { onclick: () => { undo(); t.remove(); } }, "Undo"));
  document.body.append(t);
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.remove(), 4000);
}

// ---------------------------------------------------------------------------
// Detail sheet
// ---------------------------------------------------------------------------

let editing = null;

function openDetail(item) {
  editing = item ? { ...item } : blankItem();
  const d = editing.due ? new Date(editing.due) : null;
  $("#d-title").value = editing.title;
  $("#d-date").value = d ? ymd(d) : "";
  $("#d-time").value = d && !editing.all_day ? hhmm(d) : "";
  $("#d-place").value = editing.place;
  $("#d-course").value = editing.course;
  $("#d-kind").value = editing.kind || "todo";
  $("#d-notes").value = editing.notes;
  $("#d-delete").hidden = !items.some(i => i.id === editing.id);
  $("#detail").showModal();
  if (!item) $("#d-title").focus();
}

$("#detail-form").addEventListener("submit", () => {
  if (!editing) return;
  const title = $("#d-title").value.trim();
  if (!title) return;
  Object.assign(editing, {
    title,
    place: $("#d-place").value.trim(),
    course: $("#d-course").value.trim(),
    kind: $("#d-kind").value,
    notes: $("#d-notes").value.trim(),
  }, makeDue($("#d-date").value, $("#d-time").value));
  upsertLocal(editing);
  editing = null;
});
$("#d-cancel").addEventListener("click", () => $("#detail").close());
$("#d-delete").addEventListener("click", () => {
  const item = editing;
  upsertLocal({ ...item, deleted: true });
  $("#detail").close();
  toast("Deleted", () => upsertLocal({ ...item, deleted: false }));
});
$("#btn-add").addEventListener("click", () => openDetail(null));

// ---------------------------------------------------------------------------
// Settings & theme
// ---------------------------------------------------------------------------

const darkQuery = matchMedia("(prefers-color-scheme: dark)");
function applyTheme() {
  const t = settings.theme === "auto" ? (darkQuery.matches ? "dark" : "light") : settings.theme;
  document.documentElement.dataset.theme = t;
}
darkQuery.addEventListener("change", applyTheme);

$("#btn-theme").addEventListener("click", () => {
  const order = ["auto", "dark", "light"];
  settings.theme = order[(order.indexOf(settings.theme) + 1) % order.length];
  save(LS.settings, settings);
  applyTheme();
  toast({ auto: "Theme: follow system", dark: "Theme: Cosmic Glass", light: "Theme: Liquid Silver" }[settings.theme]);
});

$("#btn-settings").addEventListener("click", () => {
  $("#s-claude").value = settings.claudeKey;
  $("#s-url").value = settings.supaUrl;
  $("#s-anon").value = settings.supaAnon;
  $("#s-sync").value = settings.syncKey;
  $("#s-theme").value = settings.theme;
  $("#s-status").textContent = syncStatus;
  $("#settings").showModal();
});
$("#s-cancel").addEventListener("click", () => $("#settings").close());
$("#settings-form").addEventListener("submit", () => {
  settings = {
    claudeKey: $("#s-claude").value.trim(),
    supaUrl: $("#s-url").value.trim().replace(/\/+$/, ""),
    supaAnon: $("#s-anon").value.trim(),
    syncKey: $("#s-sync").value.trim(),
    theme: $("#s-theme").value,
  };
  save(LS.settings, settings);
  applyTheme();
  // A newly configured database should receive everything we have locally.
  items.forEach(i => dirty.add(i.id));
  persist();
  scheduleSync(0);
});

// ---------------------------------------------------------------------------
// Sync (Supabase PostgREST, last-write-wins on updated_at)
// ---------------------------------------------------------------------------

let syncStatus = "Sync not configured";
let syncTimer = null;
let syncing = false;

function syncConfigured() {
  return settings.supaUrl && settings.supaAnon && settings.syncKey;
}
function supaHeaders(extra = {}) {
  return {
    apikey: settings.supaAnon,
    Authorization: `Bearer ${settings.supaAnon}`,
    "x-keepup-key": settings.syncKey,
    "Content-Type": "application/json",
    ...extra,
  };
}
function setSyncDot(state, msg) {
  syncStatus = msg;
  const dot = $("#sync-dot");
  dot.className = "sync-dot " + state;
  dot.title = msg;
}

function scheduleSync(delay = 30000) {
  clearTimeout(syncTimer);
  syncTimer = setTimeout(sync, delay);
}

async function sync() {
  if (!syncConfigured()) { setSyncDot("", "Sync not configured"); return; }
  if (syncing) { scheduleSync(1000); return; }
  syncing = true;
  try {
    // Push local changes first, then pull everything (a personal list is small).
    const toPush = items.filter(i => dirty.has(i.id));
    if (toPush.length) {
      const res = await fetch(`${settings.supaUrl}/rest/v1/items?on_conflict=id`, {
        method: "POST",
        headers: supaHeaders({ Prefer: "resolution=merge-duplicates,return=minimal" }),
        body: JSON.stringify(toPush),
      });
      if (!res.ok) throw new Error(`push ${res.status}: ${await res.text()}`);
      // Only clear what hasn't been edited again while the push was in flight.
      toPush.forEach(p => {
        if (items.find(i => i.id === p.id)?.updated_at === p.updated_at) dirty.delete(p.id);
      });
    }
    const res = await fetch(`${settings.supaUrl}/rest/v1/items?select=*`, { headers: supaHeaders() });
    if (!res.ok) throw new Error(`pull ${res.status}: ${await res.text()}`);
    const remote = await res.json();
    const byId = new Map(items.map(i => [i.id, i]));
    for (const r of remote) {
      const l = byId.get(r.id);
      if (!l || (!dirty.has(r.id) && new Date(r.updated_at) > new Date(l.updated_at))) byId.set(r.id, r);
    }
    items = [...byId.values()];
    persist();
    render();
    setSyncDot("ok", "Synced " + hhmm(new Date()));
  } catch (err) {
    console.warn("KeepUp sync failed", err);
    setSyncDot("err", "Sync failed — check settings (" + err.message.slice(0, 80) + ")");
  } finally {
    syncing = false;
    scheduleSync();
  }
}

document.addEventListener("visibilitychange", () => {
  if (document.visibilityState === "visible") { render(); scheduleSync(0); }
});

// ---------------------------------------------------------------------------
// Chatbox → Claude → items
// ---------------------------------------------------------------------------

const PARSE_SCHEMA = {
  type: "object",
  properties: {
    items: {
      type: "array",
      items: {
        type: "object",
        properties: {
          title: { type: "string" },
          due_date: { type: "string" },
          due_time: { type: "string" },
          place: { type: "string" },
          course: { type: "string" },
          kind: { type: "string", enum: ["assignment", "exam", "event", "todo"] },
          notes: { type: "string" },
        },
        required: ["title", "due_date", "due_time", "place", "course", "kind", "notes"],
        additionalProperties: false,
      },
    },
  },
  required: ["items"],
  additionalProperties: false,
};

function parsePrompt(knownCourses) {
  const now = new Date();
  const tz = Intl.DateTimeFormat().resolvedOptions().timeZone;
  const today = now.toLocaleDateString("en-GB", { weekday: "long", day: "numeric", month: "long", year: "numeric" });
  return `You turn quick notes, or text pasted from a course page, into to-do items for a student at HEC Paris.

Right now it is ${today}, ${hhmm(now)} (${tz}).

- A short note is one item. Pasted course material (syllabus, assignment list, announcement) can contain many: return one item per deadline, exam, presentation or deliverable. Skip anything dated before today and general information that is not something to do or attend.
- title: short and concrete, at most about 6 words (e.g. "Corporate Finance case write-up"). No dates in the title.
- due_date: YYYY-MM-DD. Resolve relative dates ("fri", "next Tuesday", "in 2 weeks") to the next matching future date. Empty string if there is no date.
- due_time: 24h HH:MM if a time is given, else empty string.
- place: room or location if mentioned, else empty string.
- course: the course name if one is identifiable${knownCourses.length ? ` — reuse one of these exact names when it matches: ${knownCourses.join(", ")}` : ""}; else empty string.
- kind: assignment (graded deliverable), exam (exam, quiz, midterm, test), event (meeting, class, social), or todo.
- notes: one line of useful detail (weight, format, submission method, who to bring), else empty string.`;
}

async function parseWithClaude(text) {
  if (!settings.claudeKey) throw new Error("Add your Claude API key in Settings (⚙) first.");
  const knownCourses = [...new Set(items.filter(i => !i.deleted).map(i => i.course).filter(Boolean))];
  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": settings.claudeKey,
      "anthropic-version": "2023-06-01",
      "anthropic-beta": "server-side-fallback-2026-07-01",
      "anthropic-dangerous-direct-browser-access": "true",
    },
    body: JSON.stringify({
      model: "claude-opus-5-5",
      max_tokens: 16000,
      fallbacks: "default",
      output_config: { effort: "low", format: { type: "json_schema", schema: PARSE_SCHEMA } },
      system: parsePrompt(knownCourses),
      messages: [{ role: "user", content: text }],
    }),
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(body?.error?.message || `Claude error ${res.status}`);
  if (body.stop_reason === "refusal") throw new Error("Claude declined to parse that text.");
  if (body.stop_reason === "max_tokens") throw new Error("That was too long to parse in one go — try pasting less.");
  const block = (body.content || []).find(b => b.type === "text");
  if (!block) throw new Error("Claude returned no result.");
  return JSON.parse(block.text).items || [];
}

let pending = [];

function showPreview(parsed) {
  pending = parsed.map(p => ({ ...p, keep: true }));
  const box = $("#preview");
  box.replaceChildren();
  if (!pending.length) {
    box.hidden = true;
    toast("Couldn't find anything to add in that.");
    return;
  }
  const addBtn = el("button", { class: "primary", onclick: commitPreview });
  const refresh = () => {
    const n = pending.filter(p => p.keep).length;
    addBtn.textContent = n === 1 ? "Add" : `Add ${n}`;
    addBtn.disabled = n === 0;
  };
  box.append(el("div", { class: "p-head" },
    el("span", {}, pending.length === 1 ? "Add this?" : `Found ${pending.length} items`),
    el("div", { class: "spacer" }),
    el("button", { class: "ghost", onclick: () => { box.hidden = true; pending = []; } }, "Cancel"),
    addBtn,
  ));
  for (const p of pending) {
    const fake = { ...makeDue(p.due_date, p.due_time), done: false };
    const meta = [dueLabel(fake).text || "No date", p.place, p.course].filter(Boolean).join(" · ");
    const cb = el("input", { type: "checkbox" });
    cb.checked = true;
    cb.addEventListener("change", () => { p.keep = cb.checked; refresh(); });
    box.append(el("label", { class: "p-item" }, cb,
      el("div", { class: "grow" }, el("div", { class: "t" }, p.title), el("div", { class: "meta" }, meta))));
  }
  refresh();
  box.hidden = false;
}

function commitPreview() {
  const chosen = pending.filter(p => p.keep);
  for (const p of chosen) {
    const item = Object.assign(blankItem(), {
      title: p.title, place: p.place, course: p.course, kind: p.kind, notes: p.notes,
    }, makeDue(p.due_date, p.due_time));
    item.updated_at = new Date().toISOString();
    items.push(item);
    dirty.add(item.id);
  }
  persist();
  render();
  scheduleSync(300);
  pending = [];
  $("#preview").hidden = true;
  toast(chosen.length === 1 ? "Added" : `Added ${chosen.length}`);
}

const input = $("#composer-input");
function autosize() {
  input.style.height = "auto";
  input.style.height = Math.min(input.scrollHeight, innerHeight * 0.4) + "px";
}
input.addEventListener("input", autosize);
input.addEventListener("keydown", e => {
  if (e.key === "Enter" && !e.shiftKey && !e.isComposing && matchMedia("(pointer: fine)").matches) {
    e.preventDefault();
    $("#composer").requestSubmit();
  }
});

$("#composer").addEventListener("submit", async e => {
  e.preventDefault();
  const text = input.value.trim();
  if (!text) return;
  const form = $("#composer");
  form.classList.add("busy");
  $("#composer-send").disabled = true;
  try {
    showPreview(await parseWithClaude(text));
    input.value = "";
    autosize();
  } catch (err) {
    toast(err.message);
  } finally {
    form.classList.remove("busy");
    $("#composer-send").disabled = false;
  }
});

// ---------------------------------------------------------------------------
// Boot
// ---------------------------------------------------------------------------

applyTheme();
render();
scheduleSync(0);
setInterval(render, 60000); // keep "Today"/"Overdue" labels fresh
if ("serviceWorker" in navigator) navigator.serviceWorker.register("sw.js").catch(() => {});
