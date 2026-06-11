# waybar-claude-usage

A standalone [Waybar](https://github.com/Alexays/Waybar) module that shows your
[Claude.ai](https://claude.ai) usage — the **5-hour session** and **7-day
weekly** windows — right in your status bar.Just
queries the Claude API with `curl`.

```
󰚩 5h:28% · 7d:4%
```

Works on plain Waybar and on [Omarchy](https://omarchy.org/) / Hyprland.

## Install

Needs `waybar`, `curl`, and `jq` (`sudo pacman -S jq curl`).

```bash
git clone https://github.com/komad1na/waybar-claude-usage.git
cd waybar-claude-usage
./setup.sh
```

`setup.sh` asks for your **sessionKey**, auto-detects your org, lets you pick a
reset-time date format, then adds the module to your Waybar config and restarts it
(existing config/style files are backed up first).

### Getting your sessionKey

In a browser logged in to Claude: **F12** → **Application** → **Cookies** →
`https://claude.ai` → `sessionKey` (starts with `sk-ant-sid...`). Paste it when
asked.

The key expires now and then — when the bar shows `stale` or `setup`, just
re-run `./setup.sh` with a fresh one.

## Reading the bar

- Two numbers: **5h session** and **7d weekly** usage, as a % of your limit.
- **Hover** for exact percentages and reset times, with time remaining, e.g.
  `resets Wed 17 Jun 11:00 (in 6d 14h)`.
- **Left-click** opens claude.ai; **right-click** refreshes now.
- You also get a **desktop notification** (via `notify-send`) when a window
  crosses the warn or danger threshold — once per crossing, re-armed after the
  window resets.

The numbers are colored by how close you are to a limit:

| Usage  | Color           |
|--------|-----------------|
| < 75 % | green `#7aa27a` |
| ≥ 75 % | amber `#d6a85a` |
| ≥ 90 % | red `#a55555`   |

Edit the colors (`C_LOW` / `C_WARN` / `C_DANGER`) and the icon at the top of
`claude-usage.sh`. The rest is tunable under `settings` in `credentials.json`:

| Setting          | Default | Meaning                                      |
|------------------|---------|----------------------------------------------|
| `warnThreshold`  | `75`    | % where numbers turn amber                   |
| `dangerThreshold`| `90`    | % where numbers turn red                     |
| `cacheTtl`       | `900`   | seconds before cached data is marked `stale` |
| `notify`         | `true`  | desktop notifications on threshold crossings |

Restart Waybar after changes.

## Notes

- **Security:** `credentials.json` holds your `sessionKey` (an account access
  token). It's `chmod 600`, git-ignored, and only ever sent to `claude.ai`.
  Don't commit or share it.
- **Number colors not showing?** Some setups (Omarchy) have a global
  `* { color }` rule that overrides per-word Pango colors. The installed style
  block handles this with `#custom-claude { color: inherit; }`.
- **Uninstall:** `./uninstall.sh` removes the module and styles (with backups),
  clears the cache, and optionally deletes your credentials.

## Support

If this module saves you a tab-switch or two, you can buy me a pizza:

[![Buy me a pizza](https://img.buymeacoffee.com/button-api/?text=Buy%20me%20a%20pizza&emoji=%F0%9F%8D%95&slug=komadina&button_colour=FFDD00&font_colour=000000&font_family=Cookie&outline_colour=000000&coffee_colour=ffffff)](https://buymeacoffee.com/komadina)
