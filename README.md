# claude-waybar

Show your Claude.ai usage (5h session + 7d weekly) right in your Omarchy/Waybar
top bar.

```
󰚩 5h 28%  7d 4%
```

**Standalone.** This is the self-contained version — just three shell scripts.
There is **no Electron app, no background daemon, no widget** to install. The
module talks to the Claude usage API directly with `curl` and renders straight
into Waybar.

## Requirements

- `waybar` (you already have it on Omarchy)
- `curl` and `jq`  →  `omarchy pkg add jq` if `jq` is missing
- An active Claude.ai login in your browser (to copy the session cookie once)

## Usage

### 1. Install

```bash
git clone https://github.com/komad1na/waybar-claude-usage.git
cd waybar-claude-usage
./setup.sh
```

The script will:

1. Ask for your **sessionKey** (see below).
2. Auto-detect your `organizationId` from the Claude API.
3. Save both to `credentials.json` (`chmod 600`, git-ignored).
4. Add the `custom/claude` module to `~/.config/waybar/config.jsonc`.
5. Append a small style block to `~/.config/waybar/style.css`.
6. Restart Waybar.

Both Waybar files are backed up (`*.bak.<timestamp>`) before they're touched.

### 2. Get your sessionKey

In your browser, while logged in to Claude:

> DevTools (**F12**) → **Application** → **Cookies** → `https://claude.ai`
> → `sessionKey`

Copy the value (it starts with `sk-ant-sid...`) and paste it when `setup.sh`
asks.

### 3. Read the bar

- The two numbers are your **5-hour session** and **7-day weekly** usage as a
  percentage of your plan limit.
- **Hover** the module for a tooltip with exact percentages and reset times.
- **Left-click** opens claude.ai. **Right-click** forces an immediate refresh.

That's it — it polls every 5 minutes on its own.

## Updating the sessionKey

The sessionKey expires periodically. When it does, the bar shows `stale` (last
known value, dimmed) or `setup`. Just re-run `./setup.sh` and paste a fresh
sessionKey — everything else stays as is.

## Colors / thresholds

Only the **percentage numbers** are colored — the icon and the `5h` / `7d`
labels keep your theme's default text color. Each number is colored by its own
window's level:

| Level  | When   | Color           |
|--------|--------|-----------------|
| normal | < 75 % | teal `#7aa2a2`  |
| warn   | ≥ 75 % | amber `#d6a85a` |
| danger | ≥ 90 % | red `#a55555`   |

If a poll fails, the whole module dims to 50 % (`stale` / `error`).

Change the colors by editing the `C_LOW` / `C_WARN` / `C_DANGER` variables at the
top of `claude-usage.sh`, and the thresholds with `warnThreshold` /
`dangerThreshold` in `credentials.json` (defaults 75 / 90). Then
`omarchy restart waybar`.

> **How the per-number color works (Omarchy gotcha).**
> The numbers are wrapped in Pango `<span color="…">` markup in
> `claude-usage.sh`. Omarchy's `style.css` has a global `* { color: @foreground }`
> rule that, when applied *directly* to a module's label, overrides Pango color
> attributes — which is why span colors look like they "don't work". The fix is
> one line in the `claude-waybar` CSS block:
> `#custom-claude { … color: inherit; }`. Making the label *inherit* its color
> (instead of having it set directly by `*`) lets the per-number `<span>` colors
> win again, while the icon and labels still fall back to the theme color.

## Other tweaks

- **Icon**: change `ICON='󰚩'` in `claude-usage.sh`.
- **One number only**: edit the `text=` line in `claude-usage.sh`.
- **Poll interval / position**: edit the `custom/claude` module in
  `~/.config/waybar/config.jsonc`, then `omarchy restart waybar`.

## How it works

A real browser `User-Agent` plus your `sessionKey` cookie is enough to reach
`https://claude.ai/api/organizations/<org>/usage` and get JSON back. Cloudflare
occasionally throws a JS challenge that `curl` can't solve, so the script caches
the last good value and shows it (marked *stale* after 15 min) instead of an
error on a failed poll. The default 5-minute poll keeps Cloudflare happy.

## Files

| File | Purpose |
|------|---------|
| `claude-usage.sh` | The Waybar module script (outputs Waybar JSON). |
| `setup.sh` | Saves your sessionKey + auto-detects org, installs the module, restarts Waybar. |
| `uninstall.sh` | Removes the module + styles from Waybar. |
| `credentials.json` | Created by setup — `{sessionKey, organizationId}`, `chmod 600`. Git-ignored. |

## Security

`credentials.json` holds your `sessionKey`, which is an access token for your
Claude account. It's written `chmod 600` and git-ignored. Don't commit it or
share it.

## Uninstall

```bash
./uninstall.sh
```

Removes the module and style block from Waybar (with backups), clears the cache,
and optionally deletes your saved credentials.
