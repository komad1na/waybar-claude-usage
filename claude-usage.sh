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

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CRED_FILE="$SCRIPT_DIR/credentials.json"
CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/waybar-claude-usage.json"
NOTIFY_STATE="${XDG_CACHE_HOME:-$HOME/.cache}/waybar-claude-usage.notified"
UA='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.0.0 Safari/537.36'
ICON='󰚩'
CURL_TIMEOUT=15  # seconds per API request
CACHE_TTL=900    # seconds before cached data counts as stale (settings.cacheTtl)
# Per-number colors (Pango markup): only the % numbers are colored, each by its
# own window's level. The icon and the "5h"/"7d" labels keep the theme default.
C_LOW='#7aa27a'    # below warnThreshold
C_WARN='#d6a85a'   # >= warnThreshold
C_DANGER='#a55555' # >= dangerThreshold

emit() { # text  tooltip  class
  jq -cn --arg text "$1" --arg tooltip "$2" --arg class "$3" \
    '{text: $text, tooltip: $tooltip, class: $class}'
}

# Fall back to the cached value on any transient failure; mark it stale once it
# is older than CACHE_TTL so a persistent outage is still visible.
fallback() { # reason
  if [ -r "$CACHE" ] && jq -e . "$CACHE" >/dev/null 2>&1; then
    local text tooltip class ts age mins
    text=$(jq -r '.text // empty' "$CACHE")
    tooltip=$(jq -r '.tooltip // empty' "$CACHE")
    class=$(jq -r '.class // "low"' "$CACHE")
    ts=$(jq -r '.ts // 0' "$CACHE")
    age=$(( $(date +%s) - ts )); mins=$(( age / 60 ))
    if [ "$age" -gt "$CACHE_TTL" ]; then
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

# The file holds an account token; quietly tighten permissions if they drifted.
perms=$(stat -c '%a' "$CONFIG" 2>/dev/null) || perms=""
if [ -n "$perms" ] && [ "$perms" != "600" ] && [ "$perms" != "400" ]; then
  chmod 600 "$CONFIG" 2>/dev/null || true
fi

SK=$(jq -r '.sessionKey // empty' "$CONFIG")
ORG=$(jq -r '.organizationId // empty' "$CONFIG")
WARN=$(jq -r '.settings.warnThreshold // 75' "$CONFIG")
DANGER=$(jq -r '.settings.dangerThreshold // 90' "$CONFIG")
DATE_FMT=$(jq -r '.settings.dateFormat // "%a %d %b %H:%M"' "$CONFIG")
# jq's // would turn an explicit false back into true, hence the comparison.
NOTIFY=$(jq -r '.settings.notify != false' "$CONFIG")
ttl=$(jq -r '.settings.cacheTtl // empty' "$CONFIG")
[[ "$ttl" =~ ^[0-9]+$ ]] && CACHE_TTL=$ttl

if [ -z "$SK" ] || [ -z "$ORG" ]; then
  emit "$ICON setup" "Incomplete credentials in $CONFIG.\nRun: $SCRIPT_DIR/setup.sh" "error"
  exit 0
fi

# The cookie goes to curl as stdin config (-K -) so the sessionKey never
# appears in the process list or in error output.
resp=$(printf 'header = "Cookie: sessionKey=%s"\n' "$SK" |
  curl -sS -K - --max-time "$CURL_TIMEOUT" --retry 2 --retry-delay 1 --compressed \
    -A "$UA" -H 'Accept: application/json' \
    "https://claude.ai/api/organizations/$ORG/usage" 2>/dev/null) || resp=""

# Only accept a complete response: both windows present and numeric. Anything
# else (Cloudflare HTML, truncated JSON) falls back to the cached value and is
# never written to the cache.
if ! jq -e '(.five_hour.utilization | type == "number") and
            (.seven_day.utilization | type == "number")' >/dev/null 2>&1 <<<"$resp"; then
  fallback "Cloudflare challenge or session expired."
  exit 0
fi

session=$(jq -r '.five_hour.utilization | floor' <<<"$resp")
weekly=$(jq -r '.seven_day.utilization | floor' <<<"$resp")
s_reset=$(jq -r '.five_hour.resets_at // empty' <<<"$resp")
w_reset=$(jq -r '.seven_day.resets_at // empty' <<<"$resp")

# Remaining time in a compact form, e.g. "1d 3h", "2h 15m", "5m".
format_duration() { # seconds
  local d=$(( $1 / 86400 )) h=$(( ($1 % 86400) / 3600 )) m=$(( ($1 % 3600) / 60 ))
  if   [ "$d" -gt 0 ]; then printf '%dd %dh' "$d" "$h"
  elif [ "$h" -gt 0 ]; then printf '%dh %dm' "$h" "$m"
  else printf '%dm' "$m"; fi
}

# Format a reset timestamp with the chosen date format, plus time left in parens.
format_reset() { # iso-timestamp
  [ -n "$1" ] || { echo "?"; return; }
  local when epoch left
  when=$(date -d "$1" "+$DATE_FMT" 2>/dev/null) || { echo "?"; return; }
  epoch=$(date -d "$1" +%s 2>/dev/null) || epoch=""
  if [ -n "$epoch" ]; then
    left=$(( epoch - $(date +%s) ))
    [ "$left" -gt 0 ] && when="$when (in $(format_duration "$left"))"
  fi
  echo "$when"
}

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
text="$ICON 5h:<span color=\"$(color_for "$session")\">${session}%</span> · 7d:<span color=\"$(color_for "$weekly")\">${weekly}%</span>"
tooltip=$(printf 'Claude usage\nSession (5h):  %3s%%   resets %s\nWeekly  (7d):  %3s%%   resets %s' \
  "$session" "$(format_reset "$s_reset")" "$weekly" "$(format_reset "$w_reset")")

# Desktop notification when a window crosses a threshold, once per crossing:
# the last notified level is remembered per window and resets when usage drops
# back below the threshold (i.e. after the window resets).
threshold_level() { # value -> 0 low, 1 warn, 2 danger
  if   [ "$1" -ge "$DANGER" ]; then echo 2
  elif [ "$1" -ge "$WARN" ];   then echo 1
  else echo 0; fi
}
notify_user() { # window-label  value  level  reset-text
  local urgency=normal; [ "$3" -ge 2 ] && urgency=critical
  notify-send -u "$urgency" -a 'Claude usage' \
    "Claude $1 usage at $2%" "Resets $4" 2>/dev/null || true
}
if [ "$NOTIFY" = "true" ] && command -v notify-send >/dev/null 2>&1; then
  cur_s=$(threshold_level "$session"); cur_w=$(threshold_level "$weekly")
  prev_s=""; prev_w=""
  [ -r "$NOTIFY_STATE" ] && read -r prev_s prev_w < "$NOTIFY_STATE" || true
  [[ "$prev_s" =~ ^[0-2]$ ]] || prev_s=0
  [[ "$prev_w" =~ ^[0-2]$ ]] || prev_w=0
  [ "$cur_s" -gt "$prev_s" ] && notify_user "5h session" "$session" "$cur_s" "$(format_reset "$s_reset")"
  [ "$cur_w" -gt "$prev_w" ] && notify_user "7d weekly" "$weekly" "$cur_w" "$(format_reset "$w_reset")"
  printf '%s %s\n' "$cur_s" "$cur_w" > "$NOTIFY_STATE"
fi

# Persist for the fallback path on the next failed poll.
mkdir -p "$(dirname "$CACHE")"
jq -cn --arg text "$text" --arg tooltip "$tooltip" --arg class "$class" --argjson ts "$(date +%s)" \
  '{text: $text, tooltip: $tooltip, class: $class, ts: $ts}' > "$CACHE"

emit "$text" "$tooltip" "$class"
