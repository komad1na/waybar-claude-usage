#!/bin/bash
# Remove the Claude usage module from Waybar and clean up local state.
set -uo pipefail
WAYBAR_CFG="$HOME/.config/waybar/config.jsonc"
WAYBAR_CSS="$HOME/.config/waybar/style.css"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/waybar-claude-usage.json"
NOTIFY_STATE="${XDG_CACHE_HOME:-$HOME/.cache}/waybar-claude-usage.notified"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -f "$WAYBAR_CFG" ] && jq -e . "$WAYBAR_CFG" >/dev/null 2>&1; then
  cp "$WAYBAR_CFG" "$WAYBAR_CFG.bak.$(date +%s)"
  tmp=$(mktemp)
  jq 'del(.["custom/claude"]) | .["modules-right"] -= ["custom/claude"]' "$WAYBAR_CFG" > "$tmp" && mv "$tmp" "$WAYBAR_CFG"
  echo "Removed module from $WAYBAR_CFG (backup made)."
fi

if [ -f "$WAYBAR_CSS" ] && grep -q 'claude-waybar:start' "$WAYBAR_CSS"; then
  sed -i '/claude-waybar:start/,/claude-waybar:end/d' "$WAYBAR_CSS"
  echo "Removed styles from $WAYBAR_CSS."
fi

rm -f "$CACHE" "$NOTIFY_STATE" && echo "Removed cache."

read -r -p "Also delete saved credentials ($SCRIPT_DIR/credentials.json)? [y/N] " ans
[[ "$ans" =~ ^[Yy]$ ]] && rm -f "$SCRIPT_DIR/credentials.json" && echo "Credentials deleted."

command -v omarchy >/dev/null && omarchy restart waybar
echo "Done."
