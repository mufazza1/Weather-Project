#!/usr/bin/env bash
#
# lib.sh — shared helpers for the Weather Bash ETL project.
#
# This file is meant to be *sourced*, not executed:
#     source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
#
# It provides logging, dependency checks, integer parsing, date helpers,
# weather fetching (with an offline mock), and JSON extraction that prefers
# `jq` when installed and falls back to pure `awk` otherwise.

# Guard against double-sourcing.
if [[ -n "${__WEATHER_LIB_SOURCED:-}" ]]; then
  return 0 2>/dev/null || exit 0
fi
__WEATHER_LIB_SOURCED=1

# ---------------------------------------------------------------------------
# Logging (always to stderr so stdout stays clean for data/pipes)
# ---------------------------------------------------------------------------
_ts() { date '+%Y-%m-%d %H:%M:%S'; }
log()  { printf '%s [INFO]  %s\n'  "$(_ts)" "$*" >&2; }
warn() { printf '%s [WARN]  %s\n'  "$(_ts)" "$*" >&2; }
err()  { printf '%s [ERROR] %s\n'  "$(_ts)" "$*" >&2; }
die()  { err "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Dependency check: require_cmd curl awk date ...
# ---------------------------------------------------------------------------
require_cmd() {
  local missing=0 c
  for c in "$@"; do
    if ! command -v "$c" >/dev/null 2>&1; then
      err "Required command not found on PATH: $c"
      missing=1
    fi
  done
  (( missing == 0 )) || die "Please install the missing dependencies and try again."
}

# ---------------------------------------------------------------------------
# Integer helpers
# ---------------------------------------------------------------------------
# Extract the first (optionally signed) integer from arbitrary text.
#   "+21°C" -> "21"   "-2" -> "-2"   "feels like 24" -> "24"
to_int() {
  printf '%s' "${1:-}" | grep -Eo '\-?[0-9]+' | head -n1
}

# True if the argument is a valid (optionally signed) integer.
is_int() {
  [[ "${1:-}" =~ ^-?[0-9]+$ ]]
}

# Absolute value of an integer.
abs_int() {
  local n="${1:-0}"
  printf '%s' "${n#-}"
}

# ---------------------------------------------------------------------------
# Date helpers (timezone aware, with test overrides)
#   TODAY_OVERRIDE / TOMORROW_OVERRIDE let tests pin the dates.
#   Falls back from GNU `date -d` to BSD `date -v` for portability.
# ---------------------------------------------------------------------------
today_date() {
  if [[ -n "${TODAY_OVERRIDE:-}" ]]; then
    printf '%s' "$TODAY_OVERRIDE"
  else
    TZ="${TZ_NAME:-UTC}" date +%F
  fi
}

tomorrow_date() {
  if [[ -n "${TOMORROW_OVERRIDE:-}" ]]; then
    printf '%s' "$TOMORROW_OVERRIDE"
  else
    TZ="${TZ_NAME:-UTC}" date -d 'tomorrow' +%F 2>/dev/null \
      || TZ="${TZ_NAME:-UTC}" date -v+1d +%F
  fi
}

# ---------------------------------------------------------------------------
# Weather fetching
#   Returns the wttr.in JSON (j1 format) on stdout.
#   If WTTR_JSON_FILE is set, reads that file instead of the network
#   (used by the test suite and for offline runs).
# ---------------------------------------------------------------------------
fetch_weather_json() {
  local city="${1:?city required}" url
  if [[ -n "${WTTR_JSON_FILE:-}" ]]; then
    [[ -f "$WTTR_JSON_FILE" ]] || { err "WTTR_JSON_FILE not found: $WTTR_JSON_FILE"; return 1; }
    cat "$WTTR_JSON_FILE"
    return 0
  fi
  url="https://wttr.in/${city}?format=j1"
  curl -fsS \
    --max-time "${CURL_TIMEOUT:-20}" \
    --retry "${CURL_RETRIES:-2}" \
    --retry-delay 2 \
    "$url"
}

# ---------------------------------------------------------------------------
# JSON extraction (prefers jq, falls back to awk)
#   All functions read the JSON document from stdin.
# ---------------------------------------------------------------------------
_have_jq() { command -v jq >/dev/null 2>&1; }

# Current observed temperature in °C.
json_current_temp() {
  local json; json="$(cat)"
  if _have_jq; then
    printf '%s' "$json" | jq -r '.current_condition[0].temp_C // empty'
  else
    printf '%s' "$json" | awk -F'"' '$2=="temp_C"{print $4; exit}'
  fi
}

# Forecast temperature at noon (12:00) for a given date (YYYY-MM-DD).
json_forecast_noon() {
  local target="${1:?target date required}" json; json="$(cat)"
  if _have_jq; then
    printf '%s' "$json" | jq -r --arg d "$target" \
      '(.weather[] | select(.date==$d) | .hourly[] | select(.time=="1200") | .tempC) // empty' \
      | head -n1
  else
    printf '%s' "$json" | awk -F'"' -v target="$target" '
      $2=="date"  { d=$4 }
      $2=="tempC" { t=$4 }
      $2=="time" && $4=="1200" && d==target { print t; exit }'
  fi
}

# Forecast average temperature for a given date (fallback if noon is missing).
json_forecast_avg() {
  local target="${1:?target date required}" json; json="$(cat)"
  if _have_jq; then
    printf '%s' "$json" | jq -r --arg d "$target" \
      '(.weather[] | select(.date==$d) | .avgtempC) // empty' | head -n1
  else
    printf '%s' "$json" | awk -F'"' -v target="$target" '
      $2=="avgtempC" { a=$4 }
      $2=="date" && $4==target { print a; exit }'
  fi
}

# ---------------------------------------------------------------------------
# Accuracy classification (based on absolute error in °C)
# ---------------------------------------------------------------------------
classify_accuracy() {
  local a; a="$(abs_int "${1:?error required}")"
  if   (( a <= 1 )); then printf 'excellent'
  elif (( a <= 2 )); then printf 'good'
  elif (( a <= 3 )); then printf 'fair'
  else                    printf 'poor'
  fi
}
