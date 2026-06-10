#!/bin/bash
# Interactive setup for the Claude usage Waybar module.
#  1. Asks for your sessionKey (grab it from the browser: DevTools -> Application
#     -> Cookies -> https://claude.ai -> sessionKey).
#  2. Auto-detects your organizationId via the Claude API.
#  3. Saves both to ./credentials.json (chmod 600).
#  4. Installs the "custom/claude" module into your Waybar config and restarts it.
#
# Re-runnable: updating the sessionKey later is just re-running this script.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRED_FILE="$SCRIPT_DIR/credentials.json"
SCRIPT="$SCRIPT_DIR/claude-usage.sh"
WAYBAR_CFG="$HOME/.config/waybar/config.jsonc"
WAYBAR_CSS="$HOME/.config/waybar/style.css"
UA='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'

for t in jq curl; do command -v "$t" >/dev/null || { echo "Missing dependency: $t"; exit 1; }; done

echo "== Claude Waybar setup =="
echo "Paste your sessionKey (DevTools -> Cookies -> claude.ai -> sessionKey)."
printf "sessionKey: "
read -r SK
SK="${SK#"${SK%%[![:space:]]*}"}"; SK="${SK%"${SK##*[![:space:]]}"}"   # trim

if [[ "$SK" != sk-ant-sid* ]]; then
  echo "That doesn't look like a sessionKey (expected to start with 'sk-ant-sid')." >&2
  exit 1
fi

echo "Detecting organization..."
orgs=$(curl -sS --max-time 20 -A "$UA" -H "Cookie: sessionKey=$SK" \
  -H 'Accept: application/json' "https://claude.ai/api/organizations" 2>/dev/null)

if ! echo "$orgs" | jq -e 'type == "array"' >/dev/null 2>&1; then
  echo "Could not fetch organizations (Cloudflare challenge or invalid key). Try again." >&2
  exit 1
fi

# chat-capable orgs only; prefer a team org, else the first one (matches the app).
ORG=$(echo "$orgs" | jq -r '
  [ .[]? | select((.capabilities // []) | index("chat")) ] as $chat
  | ( ($chat | map(select(.raven_type=="team")) | .[0]) // $chat[0] )
  | (.uuid // .id) // empty')

if [ -z "$ORG" ] || [ "$ORG" = "null" ]; then
  echo "No chat-enabled organization found for this session key." >&2
  exit 1
fi
ORG_NAME=$(echo "$orgs" | jq -r --arg id "$ORG" '.[] | select((.uuid // .id)==$id) | .name // "?"')
echo "Found organization: $ORG_NAME ($ORG)"

# Save credentials.
umask 077
jq -cn --arg sk "$SK" --arg org "$ORG" '{sessionKey:$sk, organizationId:$org}' > "$CRED_FILE"
chmod 600 "$CRED_FILE"
echo "Saved credentials -> $CRED_FILE (chmod 600)"

chmod +x "$SCRIPT"

# Verify it actually works now.
echo "Testing usage fetch..."
out=$("$SCRIPT")
echo "  $(echo "$out" | jq -r '.text')"
if echo "$out" | jq -e '.class == "error"' >/dev/null 2>&1; then
  echo "Warning: fetch returned an error state. Cloudflare may be challenging; it usually clears on the next poll." >&2
fi

# ---- Install into Waybar (only if config is plain JSON we can edit safely) ----
install_waybar() {
  [ -f "$WAYBAR_CFG" ] || { echo "No $WAYBAR_CFG; skipping Waybar install."; return 1; }
  if ! jq -e . "$WAYBAR_CFG" >/dev/null 2>&1; then
    echo "Your $WAYBAR_CFG has comments/JSONC; add the module manually (see README)."; return 1
  fi
  cp "$WAYBAR_CFG" "$WAYBAR_CFG.bak.$(date +%s)"
  local tmp; tmp=$(mktemp)
  jq --arg exec "$SCRIPT" '
    .["custom/claude"] = {
      exec: $exec, "return-type": "json", interval: 300, signal: 11,
      "on-click": "xdg-open https://claude.ai",
      "on-click-right": "pkill -RTMIN+11 waybar"
    }
    | if (.["modules-right"] | index("custom/claude")) then .
      else .["modules-right"] as $m | ($m | index("custom/stats")) as $i
        | if $i then .["modules-right"] = ($m[0:$i] + ["custom/claude"] + $m[$i:])
          else .["modules-right"] = ($m + ["custom/claude"]) end
      end
  ' "$WAYBAR_CFG" > "$tmp" && mv "$tmp" "$WAYBAR_CFG"
  echo "Updated $WAYBAR_CFG (backup made)."

  if [ -f "$WAYBAR_CSS" ] && ! grep -q 'claude-waybar:start' "$WAYBAR_CSS"; then
    cat >> "$WAYBAR_CSS" <<'CSS'

/* claude-waybar:start */
/* color:inherit lets the per-number Pango <span> colors (set in
   claude-usage.sh) win over a global "* { color }" rule, so only the % numbers
   are colored while the icon and 5h/7d labels keep the theme default. */
#custom-claude { min-width: 12px; margin: 0 7.5px; color: inherit; }
#custom-claude.error, #custom-claude.stale { opacity: 0.5; }
/* claude-waybar:end */
CSS
    echo "Appended styles to $WAYBAR_CSS."
  fi
  return 0
}

if install_waybar; then
  if command -v omarchy >/dev/null; then omarchy restart waybar
  else pkill waybar 2>/dev/null; (waybar >/dev/null 2>&1 &) ; fi
  echo "Waybar restarted."
fi

echo "Done."
