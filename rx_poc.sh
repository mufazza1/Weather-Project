#!/usr/bin/env bash
#
# rx_poc.sh — Weather forecast-accuracy ETL.
#
# Each run:
#   1. Fetches Casablanca weather from wttr.in (JSON).
#   2. Records today's *observed* temperature and the *forecast for tomorrow*.
#   3. Once at least two daily readings exist, compares yesterday's
#      forecast-for-today against today's observed temperature and stores
#      the error and a quality rating in the history file.
#
# Intended to run once per day (see README for cron / Task Scheduler setup).

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

# ---------------------------------------------------------------------------
# Configuration (override via environment variables)
# ---------------------------------------------------------------------------
CITY="${CITY:-Casablanca}"
TZ_NAME="${TZ_NAME:-Africa/Casablanca}"
DATA_DIR="${DATA_DIR:-$SCRIPT_DIR}"
READINGS_FILE="${READINGS_FILE:-$DATA_DIR/weather_readings.tsv}"
HISTORY_FILE="${HISTORY_FILE:-$DATA_DIR/historical_fc_accuracy.tsv}"

# TSV schemas (tab-separated)
#   READINGS_FILE: date  obs_temp  fc_tomorrow
#   HISTORY_FILE : date  obs_temp  forecast  error  rating
READINGS_HEADER=$'date\tobs_temp\tfc_tomorrow'
HISTORY_HEADER=$'date\tobs_temp\tforecast\terror\trating'

# ---------------------------------------------------------------------------
# Readings file helpers
# ---------------------------------------------------------------------------
ensure_readings_file() {
  [[ -f "$READINGS_FILE" ]] || printf '%s\n' "$READINGS_HEADER" > "$READINGS_FILE"
}

last_reading_date() {
  [[ -f "$READINGS_FILE" ]] || return 0
  tail -n +2 "$READINGS_FILE" | tail -n1 | cut -f1
}

# Append today's reading. If a reading for the same date already exists,
# replace it (so re-running on the same day refreshes rather than duplicates).
record_reading() {
  local date="$1" obs="$2" fc="$3" last tmp
  last="$(last_reading_date)"
  if [[ "$last" == "$date" ]]; then
    warn "Reading for $date already exists — refreshing it."
    tmp="$(mktemp)"
    awk -F'\t' -v d="$date" 'NR==1 || $1!=d' "$READINGS_FILE" > "$tmp"
    mv "$tmp" "$READINGS_FILE"
  fi
  printf '%s\t%s\t%s\n' "$date" "$obs" "$fc" >> "$READINGS_FILE"
}

reading_count() {
  [[ -f "$READINGS_FILE" ]] || { printf '0'; return 0; }
  tail -n +2 "$READINGS_FILE" | grep -c . || true
}

# ---------------------------------------------------------------------------
# History file helpers
# ---------------------------------------------------------------------------
ensure_history_file() {
  [[ -f "$HISTORY_FILE" ]] || printf '%s\n' "$HISTORY_HEADER" > "$HISTORY_FILE"
}

history_has_date() {
  [[ -f "$HISTORY_FILE" ]] || return 1
  tail -n +2 "$HISTORY_FILE" | cut -f1 | grep -qx "$1"
}

# ---------------------------------------------------------------------------
# Accuracy: compare the previous day's forecast (made for "today")
# against today's observed temperature.
# ---------------------------------------------------------------------------
compute_and_store_accuracy() {
  local today="$1" rows prev_fc today_obs error rating
  rows="$(reading_count)"
  if (( rows < 2 )); then
    log "Only $rows reading(s) so far — need 2 to score accuracy. Run again tomorrow."
    return 0
  fi

  prev_fc="$(tail -n +2 "$READINGS_FILE" | tail -n2 | head -n1 | cut -f3)"
  today_obs="$(tail -n +2 "$READINGS_FILE" | tail -n1 | cut -f2)"
  prev_fc="$(to_int "$prev_fc")"
  today_obs="$(to_int "$today_obs")"
  is_int "$prev_fc"   || die "Could not parse previous forecast from $READINGS_FILE."
  is_int "$today_obs" || die "Could not parse today's observation from $READINGS_FILE."

  error=$(( prev_fc - today_obs ))
  rating="$(classify_accuracy "$error")"
  log "Forecast error for $today: ${error}°C (forecast ${prev_fc}°C vs observed ${today_obs}°C) → $rating"

  ensure_history_file
  if history_has_date "$today"; then
    warn "History already contains a row for $today — not appending a duplicate."
    return 0
  fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$today" "$today_obs" "$prev_fc" "$error" "$rating" >> "$HISTORY_FILE"
  log "Appended accuracy record to $HISTORY_FILE"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  require_cmd curl awk date grep cut

  local today tomorrow json obs_temp fc_raw fc_temp
  today="$(today_date)"
  tomorrow="$(tomorrow_date)"

  log "Fetching weather for ${CITY} (today=${today}, tomorrow=${tomorrow}) ..."
  json="$(fetch_weather_json "$CITY")" || die "Failed to fetch weather data for ${CITY}."

  obs_temp="$(printf '%s' "$json" | json_current_temp)"
  obs_temp="$(to_int "$obs_temp")"
  is_int "$obs_temp" || die "Could not parse current temperature from weather data."

  fc_raw="$(printf '%s' "$json" | json_forecast_noon "$tomorrow")"
  if ! is_int "$(to_int "$fc_raw")"; then
    warn "Noon forecast for $tomorrow unavailable — using tomorrow's average instead."
    fc_raw="$(printf '%s' "$json" | json_forecast_avg "$tomorrow")"
  fi
  fc_temp="$(to_int "$fc_raw")"
  is_int "$fc_temp" || die "Could not parse tomorrow's forecast temperature."

  log "Observed ${today}: ${obs_temp}°C  |  Forecast for ${tomorrow}: ${fc_temp}°C"

  ensure_readings_file
  record_reading "$today" "$obs_temp" "$fc_temp"
  compute_and_store_accuracy "$today"

  log "Done."
}

main "$@"
