#!/usr/bin/env bash
#
# weekly_stats.sh — summarize recent forecast accuracy.
#
# Reads the history file produced by rx_poc.sh and prints a report over the
# last N data rows (default 7). "Accuracy" is the signed error in °C
# (forecast - observed); it is judged by distance from zero, so the best day
# is the one closest to 0 and the worst is the one farthest from it.
#
# Usage: ./weekly_stats.sh [N]

set -euo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

DATA_DIR="${DATA_DIR:-$SCRIPT_DIR}"
HISTORY_FILE="${HISTORY_FILE:-$DATA_DIR/historical_fc_accuracy.tsv}"
WINDOW="${1:-7}"

is_int "$WINDOW" && (( WINDOW > 0 )) || die "Window must be a positive integer (got: '$WINDOW')."

if [[ ! -f "$HISTORY_FILE" ]]; then
  die "No historical data found at $HISTORY_FILE. Run rx_poc.sh first."
fi

# History columns: date  obs_temp  forecast  error  rating  ($4 = error, $5 = rating)
# Skip the header (line 1) and keep the last WINDOW data rows.
data="$(tail -n +2 "$HISTORY_FILE" | tail -n "$WINDOW")"

if [[ -z "$data" ]]; then
  log "Not enough data for a report yet (history is empty)."
  exit 0
fi

days="$(printf '%s\n' "$data" | grep -c .)"

# Average / best / worst, all based on the absolute error.
read -r avg best worst <<<"$(printf '%s\n' "$data" | awk -F'\t' '
  {
    e = $4; if (e < 0) e = -e
    sum += e
    if (NR == 1 || e < min) min = e
    if (NR == 1 || e > max) max = e
  }
  END {
    if (NR > 0) printf "%.2f\t%d\t%d", sum/NR, min, max
    else        printf "0\t0\t0"
  }')"

# Distribution across rating categories (exact match on the rating column).
read -r excellent good fair poor <<<"$(printf '%s\n' "$data" | awk -F'\t' '
  { c[$5]++ }
  END { printf "%d\t%d\t%d\t%d", c["excellent"], c["good"], c["fair"], c["poor"] }')"

printf 'Weekly Forecast Accuracy Report\n'
printf -- '--------------------------------\n'
printf 'Days analyzed:    %s\n'   "$days"
printf 'Mean abs error:   %s °C\n' "$avg"
printf 'Best (closest):   %s °C\n' "$best"
printf 'Worst (farthest): %s °C\n' "$worst"
printf '\n'
printf 'Accuracy distribution:\n'
printf '  Excellent (<=1°C): %s\n' "$excellent"
printf '  Good      (<=2°C): %s\n' "$good"
printf '  Fair      (<=3°C): %s\n' "$fair"
printf '  Poor      ( >3°C): %s\n' "$poor"
