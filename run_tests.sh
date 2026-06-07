#!/usr/bin/env bash
#
# run_tests.sh — offline test suite for the Weather ETL project.
#
# Uses a saved wttr.in response (tests/fixtures/wttr_sample.json) so the tests
# need no network access. The fixture contains dates 2026-06-07/08/09.

set -uo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

FIXTURE="$SCRIPT_DIR/tests/fixtures/wttr_sample.json"

PASS=0
FAIL=0

check() {
  local desc="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    printf '  ok   %s\n' "$desc"
    PASS=$((PASS + 1))
  else
    printf '  FAIL %s\n        expected: [%s]\n        actual:   [%s]\n' "$desc" "$expected" "$actual"
    FAIL=$((FAIL + 1))
  fi
}

[[ -f "$FIXTURE" ]] || { echo "Missing fixture: $FIXTURE"; exit 1; }

echo "== Unit: integer + classification helpers =="
check "to_int '+21°C'"        "21"   "$(to_int '+21°C')"
check "to_int '-2'"           "-2"   "$(to_int '-2')"
check "to_int 'feels 24c'"    "24"   "$(to_int 'feels 24c')"
check "is_int '5' (true)"     "yes"  "$(is_int 5 && echo yes || echo no)"
check "is_int 'x' (false)"    "no"   "$(is_int x && echo yes || echo no)"
check "abs_int -3"            "3"    "$(abs_int -3)"
check "classify 0"            "excellent" "$(classify_accuracy 0)"
check "classify -1"          "excellent" "$(classify_accuracy -1)"
check "classify 2"           "good"      "$(classify_accuracy 2)"
check "classify -3"          "fair"      "$(classify_accuracy -3)"
check "classify 5"           "poor"      "$(classify_accuracy 5)"

echo "== Integration: JSON extraction from fixture =="
check "current temp"          "21"   "$(json_current_temp        < "$FIXTURE")"
check "noon forecast 06-09"   "24"   "$(json_forecast_noon  '2026-06-09' < "$FIXTURE")"
check "avg forecast 06-09"    "22"   "$(json_forecast_avg   '2026-06-09' < "$FIXTURE")"
check "noon missing date"     ""     "$(json_forecast_noon  '2030-01-01' < "$FIXTURE")"

echo "== End-to-end: rx_poc.sh ETL (offline, date-pinned) =="
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Seed a prior reading for 2026-06-08 (obs=20, forecast-for-tomorrow=24).
printf 'date\tobs_temp\tfc_tomorrow\n'      >  "$WORK/weather_readings.tsv"
printf '2026-06-08\t20\t24\n'               >> "$WORK/weather_readings.tsv"

# Run for "today"=2026-06-09 using the fixture (current temp = 21°C).
# Forecast lookup is pointed at 06-09 (present in the fixture) so parsing succeeds.
DATA_DIR="$WORK" \
WTTR_JSON_FILE="$FIXTURE" \
TODAY_OVERRIDE="2026-06-09" \
TOMORROW_OVERRIDE="2026-06-09" \
  bash "$SCRIPT_DIR/rx_poc.sh" >/dev/null 2>&1

# A new reading for 06-09 should have been recorded (obs=21).
check "reading appended (06-09 obs)" "21" \
  "$(awk -F'\t' '$1=="2026-06-09"{print $2}' "$WORK/weather_readings.tsv")"

# Accuracy: yesterday's forecast (24) - today's observed (21) = 3 -> fair.
check "history error value"  "3"    "$(awk -F'\t' '$1=="2026-06-09"{print $4}' "$WORK/historical_fc_accuracy.tsv")"
check "history rating"       "fair" "$(awk -F'\t' '$1=="2026-06-09"{print $5}' "$WORK/historical_fc_accuracy.tsv")"

# Idempotency: a second run on the same day must not duplicate rows.
DATA_DIR="$WORK" WTTR_JSON_FILE="$FIXTURE" \
TODAY_OVERRIDE="2026-06-09" TOMORROW_OVERRIDE="2026-06-09" \
  bash "$SCRIPT_DIR/rx_poc.sh" >/dev/null 2>&1
check "no duplicate history row" "1" \
  "$(awk -F'\t' '$1=="2026-06-09"' "$WORK/historical_fc_accuracy.tsv" | grep -c .)"
check "no duplicate reading row" "1" \
  "$(awk -F'\t' '$1=="2026-06-09"' "$WORK/weather_readings.tsv" | grep -c .)"

echo "== Integration: weekly_stats.sh report =="
HIST="$WORK/hist_report.tsv"
{
  printf 'date\tobs_temp\tforecast\terror\trating\n'
  printf '2026-06-01\t20\t21\t1\texcellent\n'
  printf '2026-06-02\t22\t19\t-3\tfair\n'
  printf '2026-06-03\t18\t23\t5\tpoor\n'
  printf '2026-06-04\t25\t25\t0\texcellent\n'
  printf '2026-06-05\t24\t26\t2\tgood\n'
} > "$HIST"

report="$(HISTORY_FILE="$HIST" bash "$SCRIPT_DIR/weekly_stats.sh")"
check "days analyzed"    "Days analyzed:    5"     "$(printf '%s\n' "$report" | grep 'Days analyzed:')"
check "mean abs error"   "Mean abs error:   2.20 °C" "$(printf '%s\n' "$report" | grep 'Mean abs error:')"
check "best closest"     "Best (closest):   0 °C"  "$(printf '%s\n' "$report" | grep 'Best (closest):')"
check "worst farthest"   "Worst (farthest): 5 °C"  "$(printf '%s\n' "$report" | grep 'Worst (farthest):')"
check "excellent count"  "  Excellent (<=1°C): 2"  "$(printf '%s\n' "$report" | grep 'Excellent')"
check "poor count"       "  Poor      ( >3°C): 1"  "$(printf '%s\n' "$report" | grep 'Poor')"

echo
echo "-------------------------------------"
printf 'Results: %d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 )) || exit 1
