# KeepUp

A personal to-do and deadline tracker. It has two apps that share one synced list:

- **Mac app** (SwiftUI). It has a main window and a **desktop widget** pinned to your desktop that lists what's due next, soonest first.
- **Phone app** (an installable web app). Add it to your Android home screen from Chrome.

Both apps use OnCue's two looks: **Cosmic Glass** in dark mode and **Liquid Silver** in light mode. By default they follow the system setting, and you can switch manually.

**Adding things:** type into the chatbox, e.g. `corp fin case due fri 23:59 room T102`, and Claude turns it into an item. You can also **paste a whole Blackboard page or syllabus**. Claude lists every deadline it finds and you tick the ones to add. The **+** button opens a manual form.

The list shows only the title and the deadline. Click an item to see or edit the place, course/tag, type and notes. There are no notifications.

---

## One-time setup (about 10 minutes)

### 1. Sync database (Supabase, free)

1. Create a free project at [supabase.com](https://supabase.com).
2. Pick a long random passphrase. This is your **sync key**.
3. Open **SQL Editor** and paste in [`supabase/schema.sql`](supabase/schema.sql). Replace both `CHANGE-ME` with your passphrase, then click **Run**.
4. Go to **Project Settings → API** and copy the **Project URL** and the **anon public** key.

The table only accepts requests that carry your sync key. The key and the anon key never go in this repo; you paste them into each app.

### 2. Claude API key

Create a key at [console.anthropic.com](https://console.anthropic.com) under **API Keys**. It's used only by the chatbox, and each entry costs a fraction of a cent.

### 3. Mac app

- **Download:** go to **Actions → Build KeepUp DMG**, open the latest run and download `KeepUp-dmg`. Open the DMG and drag KeepUp to Applications. The first time, right-click KeepUp and choose **Open**, because the app is ad-hoc signed.
- **Or build it yourself:** `cd mac && ./build_app.sh` (needs Xcode command-line tools).
- Open **KeepUp → Settings (⌘,)**:
  - paste the Claude key, the Supabase URL, the anon key and the sync key;
  - turn on **Open KeepUp at login** so the desktop widget is always there.
- **Desktop widget:** drag it anywhere and it remembers the position. Click the circle to mark an item done, or click the title to open it. Toggle the widget with **⇧⌘W**.

### 4. Android phone

1. Turn on GitHub Pages once: **repo Settings → Pages → Source: GitHub Actions**. Then re-run **Actions → Publish phone app**.
2. On your phone, open **https://awielgosx.github.io/KeepUp/** in Chrome, then **⋮ → Add to Home screen / Install app**.
3. Tap **⚙** and paste the same four values.

The page itself is public but holds no data. Your items and keys stay on your devices and in your Supabase project.

---

## How it works

| Piece | Where |
|---|---|
| Phone app (plain HTML/CSS/JS, no build step) | `web/` |
| Mac app (Swift package, macOS 13+) | `mac/` |
| Database table + access rule | `supabase/schema.sql` |

- Each device keeps a local copy and works offline. Every 30 seconds, on every change and whenever the app is opened, it pushes its edits and pulls the full list. If two devices edit the same item, the newest edit wins.
- The chatbox sends your text, today's date and your existing course names to Claude (`claude-opus-5-5`, low effort) with a strict JSON schema. The result is shown for you to confirm before anything is saved. The prompt lives in `web/app.js` and `mac/Sources/KeepUp/ClaudeParser.swift`; keep the two in step.
- The desktop widget is a borderless window that sits at desktop level on all Spaces. A real WidgetKit widget would require a paid Apple Developer account.
