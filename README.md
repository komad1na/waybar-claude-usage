# waybar-claude-usage

A standalone [Waybar](https://github.com/Alexays/Waybar) module that shows your
[Claude.ai](https://claude.ai) usage — both the **5-hour session** and **7-day
weekly** windows — directly in your status bar.

```
󰚩 5h 28%  7d 4%
```

It works on plain Waybar and on [Omarchy](https://omarchy.org/) / Hyprland
setups.

## What it does

- Reads your Claude usage straight from the Claude API with `curl` — **no
  Electron app, no background daemon, no browser extension** to install.
- Shows two percentages: how much of your **5-hour session** limit and your
  **7-day weekly** limit you've used.
- Colors the numbers by how close you are to a limit (teal → amber → red), so a
  quick glance tells you whether you're fine.
- Hover for a tooltip with exact percentages and the next reset times.
- Survives Cloudflare hiccups: if a poll fails it keeps showing the last known
  value (dimmed and marked *stale*) instead of an error.

## How it works

A real browser `User-Agent` plus your account's `sessionKey` cookie is enough to
reach `https://claude.ai/api/organizations/<org>/usage` and get JSON back. The
module polls that endpoint every 5 minutes and renders the result as Waybar
JSON. Cloudflare occasionally serves a JS challenge that `curl` can't solve, so
the script caches the last good value and shows it (marked *stale* after 15 min)
instead of failing.

## Requirements

- `waybar`
- `curl` and `jq`
- An active Claude.ai login in a browser (to copy the session cookie once)

On Arch-based systems: `sudo pacman -S jq curl` (or `omarchy pkg add jq` on
Omarchy).

## Installation

```bash
git clone https://github.com/komad1na/waybar-claude-usage.git
cd waybar-claude-usage
./setup.sh
```

`setup.sh` will:

1. Ask for your **sessionKey** (see below).
2. Auto-detect your `organizationId` from the Claude API.
3. Let you pick how **reset times** are formatted in the tooltip (a small menu).
4. Save everything to `credentials.json` (`chmod 600`, git-ignored).
5. Add the `custom/claude` module to `~/.config/waybar/config.jsonc`.
6. Append a small style block to `~/.config/waybar/style.css`.
7. Restart Waybar (via `omarchy restart waybar` if available, otherwise it
   restarts `waybar` directly).

Both Waybar files are backed up (`*.bak.<timestamp>`) before they're touched. If
your `config.jsonc` contains comments/JSONC that can't be edited automatically,
the script tells you to add the module manually.

### Getting your sessionKey

In a browser, while logged in to Claude:

> DevTools (**F12**) → **Application** → **Cookies** → `https://claude.ai`
> → `sessionKey`

Copy the value (it starts with `sk-ant-sid...`) and paste it when `setup.sh`
asks for it.

## Usage

Once installed, the module sits in your bar and updates itself:

- The two numbers are your **5-hour session** and **7-day weekly** usage as a
  percentage of your plan limit.
- **Hover** for a tooltip with exact percentages and reset times — each reset
  shows the time remaining in parentheses, e.g. `resets Wed 17 Jun 11:00
  (in 6d 14h)`.
- **Left-click** opens claude.ai. **Right-click** forces an immediate refresh.

### Updating the sessionKey

The sessionKey expires periodically. When it does, the bar shows `stale` (last
known value, dimmed) or `setup`. Re-run `./setup.sh` and paste a fresh
sessionKey — everything else stays as is.

## Colors & thresholds

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
`dangerThreshold` in `credentials.json` (defaults 75 / 90). Then restart Waybar.

> **If the number colors don't show up:** some setups (Omarchy included) have a
> global `* { color: … }` rule in `style.css`. When that color is applied
> *directly* to a module's label it overrides the per-number Pango `<span>`
> colors. The installed style block works around this with
> `#custom-claude { … color: inherit; }` — making the label *inherit* its color
> instead of having it set directly lets the `<span>` colors win again.

## Customization

- **Icon**: change `ICON='󰚩'` in `claude-usage.sh`.
- **Show one number only**: edit the `text=` line in `claude-usage.sh`.
- **Reset-time format**: chosen during `setup.sh` and stored as
  `settings.dateFormat` (a `date(1)` format string) in `credentials.json`.
  Re-run `setup.sh` to change it, or edit the value directly.
- **Poll interval / position**: edit the `custom/claude` module in
  `~/.config/waybar/config.jsonc`, then restart Waybar.

## Files

| File | Purpose |
|------|---------|
| `claude-usage.sh` | The Waybar module script (outputs Waybar JSON). |
| `setup.sh` | Saves the sessionKey + auto-detects the org, installs the module, restarts Waybar. |
| `uninstall.sh` | Removes the module + styles from Waybar. |
| `credentials.json` | Created by setup — `{sessionKey, organizationId}`, `chmod 600`. Git-ignored. |

## Security

`credentials.json` holds your `sessionKey`, which is an access token for your
Claude account. It is written `chmod 600` and is git-ignored. Don't commit it or
share it. This project only ever sends the key to `claude.ai`.

## Uninstall

```bash
./uninstall.sh
```

Removes the module and style block from Waybar (with backups), clears the cache,
and optionally deletes the saved credentials.
