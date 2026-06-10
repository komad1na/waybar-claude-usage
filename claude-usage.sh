#!/bin/bash
# Claude usage for Waybar (standalone).
#
# Queries the claude.ai usage API directly with curl: a real browser
# User-Agent + the sessionKey cookie is enough to pass Cloudflare most of the
# time. Cloudflare occasionally serves a JS challenge curl cannot solve, so on
# any transient failure we fall back to the last good value from a cache file
# instead of showing an error. Output is Waybar JSON.
#
# Credentials are read from ./credentials.json (created by setup.sh).

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRED_FILE="$SCRIPT_DIR/credentials.json"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/waybar-claude-usage.json"
UA='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'
ICON='󰚩'
# Per-number colors (Pango markup): only the % numbers are colored, each by its
# own window's level. The icon and the "5h"/"7d" labels keep the theme default.
C_LOW='#7aa2a2'    # below warnThreshold
C_WARN='#d6a85a'   # >= warnThreshold
C_DANGER='#a55555' # >= dangerThreshold

emit() { # text  tooltip  class
  jq -cn --arg text "$1" --arg tooltip "$2" --arg class "$3" \
    '{text: $text, tooltip: $tooltip, class: $class}'
}

# Fall back to the cached value on any transient failure; mark it stale once it
# is older than ~15 min so a persistent outage is still visible.
fallback() { # reason
  if [ -r "$CACHE" ]; then
    local text tooltip class ts age mins
    text=$(jq -r '.text' "$CACHE"); tooltip=$(jq -r '.tooltip' "$CACHE")
    class=$(jq -r '.class' "$CACHE"); ts=$(jq -r '.ts // 0' "$CACHE")
    age=$(( $(date +%s) - ts )); mins=$(( age / 60 ))
    if [ "$age" -gt 900 ]; then
      emit "$text" "$tooltip"$'\n\n'"⚠ stale (${mins}m old): $1" "stale"
    else
      emit "$text" "$tooltip" "$class"
    fi
  else
    emit "$ICON ?" "$1" "error"
  fi
}

# Resolve the credentials file written by setup.sh.
CONFIG=""
if [ -r "$CRED_FILE" ] && [ -n "$(jq -r '.sessionKey // empty' "$CRED_FILE" 2>/dev/null)" ]; then
  CONFIG="$CRED_FILE"
fi

if [ -z "$CONFIG" ]; then
  emit "$ICON setup" "No Claude credentials found.\nRun: $SCRIPT_DIR/setup.sh" "error"
  exit 0
fi

SK=$(jq -r '.sessionKey // empty' "$CONFIG")
ORG=$(jq -r '.organizationId // empty' "$CONFIG")
WARN=$(jq -r '.settings.warnThreshold // 75' "$CONFIG")
DANGER=$(jq -r '.settings.dangerThreshold // 90' "$CONFIG")

if [ -z "$SK" ] || [ -z "$ORG" ]; then
  emit "$ICON setup" "Incomplete credentials in $CONFIG.\nRun: $SCRIPT_DIR/setup.sh" "error"
  exit 0
fi

resp=$(curl -sS --max-time 15 \
  -A "$UA" \
  -H "Cookie: sessionKey=$SK" \
  -H 'Accept: application/json' \
  "https://claude.ai/api/organizations/$ORG/usage" 2>/dev/null)

# Valid JSON with the expected shape? Otherwise fall back to the cached value.
if ! echo "$resp" | jq -e '.five_hour.utilization' >/dev/null 2>&1; then
  fallback "Cloudflare challenge or session expired."
  exit 0
fi

session=$(echo "$resp" | jq -r '.five_hour.utilization // 0 | floor')
weekly=$(echo "$resp" | jq -r '.seven_day.utilization // 0 | floor')
s_reset=$(echo "$resp" | jq -r '.five_hour.resets_at // empty')
w_reset=$(echo "$resp" | jq -r '.seven_day.resets_at // empty')

fmt() { [ -n "$1" ] && date -d "$1" '+%a %d %b %H:%M' 2>/dev/null || echo "?"; }

# Class is driven by whichever window is closest to its limit.
peak=$session
[ "$weekly" -gt "$peak" ] && peak=$weekly
class="low"
[ "$peak" -ge "$WARN" ]   && class="warn"
[ "$peak" -ge "$DANGER" ] && class="danger"

# Color each % by its own window's level (Pango markup); labels/icon stay default.
color_for() { # value
  if   [ "$1" -ge "$DANGER" ]; then printf '%s' "$C_DANGER"
  elif [ "$1" -ge "$WARN" ];   then printf '%s' "$C_WARN"
  else printf '%s' "$C_LOW"; fi
}
text="$ICON 5h <span color=\"$(color_for "$session")\">${session}%</span>  7d <span color=\"$(color_for "$weekly")\">${weekly}%</span>"
tooltip=$(printf 'Claude usage\nSession (5h):  %3s%%   resets %s\nWeekly  (7d):  %3s%%   resets %s' \
  "$session" "$(fmt "$s_reset")" "$weekly" "$(fmt "$w_reset")")

# Persist for the fallback path on the next failed poll.
mkdir -p "$(dirname "$CACHE")"
jq -cn --arg text "$text" --arg tooltip "$tooltip" --arg class "$class" --argjson ts "$(date +%s)" \
  '{text: $text, tooltip: $tooltip, class: $class, ts: $ts}' > "$CACHE"

emit "$text" "$tooltip" "$class"
