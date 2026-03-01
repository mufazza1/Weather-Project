#!/usr/bin/env bash
set -euo pipefail

# -----------------------------
# Config
# -----------------------------
CITY="Casablanca"
TZ_NAME="Africa/Casablanca"

LOG_FILE="rx_poc.log"
HISTORY_FILE="historical_fc_accuracy.tsv"

# -----------------------------
# Helpers
# -----------------------------
# Keep only digits and minus sign (e.g. "18°C" -> "18", "-2" stays "-2")
to_int() {
  echo "$1" | tr -cd '0-9-'
}

# -----------------------------
# 1) Get weather data (clean output, no ASCII art parsing)
# wttr format:
#   %t  = current temperature
#   %T  = feels like
#   %m  = condition text
#   %w  = wind
# Tomorrow noon forecast:
#   wttr allows day offset: 1 means tomorrow
#   %t is temperature for that time block
# -----------------------------

# Current temperature
obs_temp_raw="$(curl -fsS "https://wttr.in/${CITY}?format=%t")"
obs_temp_int="$(to_int "$obs_temp_raw")"

# Forecast temp around noon tomorrow (approx):
# Using format with day offset is not perfect for "noon", but most stable in wttr:
# We'll use "tomorrow" general temp as forecast proxy.
# If you want *more detailed* later, we can switch to JSON API.
fc_temp_raw="$(curl -fsS "https://wttr.in/${CITY}?format=1")"
# Extract first "+NN" or "-NN" from the one-line summary
fc_temp_int="$(echo "$fc_temp_raw" | grep -Eo '[+-]?[0-9]+' | head -n1 | tr -d '+')"

# Fallback if forecast parsing fails
if [[ -z "${fc_temp_int:-}" ]]; then
  fc_temp_int="$obs_temp_int"
fi

echo "The current Temperature of $CITY: ${obs_temp_int} °C"
echo "The forecasted temperature for tomorrow (summary) for $CITY: ${fc_temp_int} °C"

# -----------------------------
# 2) Date values (timezone-based)
# -----------------------------
year="$(TZ="$TZ_NAME" date +%Y)"
month="$(TZ="$TZ_NAME" date +%m)"
day="$(TZ="$TZ_NAME" date +%d)"

# -----------------------------
# 3) Write log line (TAB-separated)
# columns: year month day obs_temp fc_temp
# -----------------------------
if [[ ! -s "$LOG_FILE" ]]; then
printf "%s\t%s\t%s\t%s\t%s\n" "$year" "$month" "$day" "$obs_temp_int" "$fc_temp_int" >> "$LOG_FILE"
fi
# -----------------------------
# 4) Calculate accuracy using last two rows (needs at least 2 lines)
# accuracy = yesterday_forecast - today_observed
# -----------------------------
lines="$(wc -l < "$LOG_FILE" | tr -d ' ')"

if (( lines < 2 )); then
  echo "Not enough log history yet (need 2 runs). Run again tomorrow."
  exit 0
fi

# Read values from last 2 rows (TAB-separated)
yesterday_fc="$(tail -n 2 "$LOG_FILE" | head -1 | cut -d " " -f5)"
today_temp="$(tail -n 1 "$LOG_FILE" | cut -d " " -f4)"

# Ensure they are integers
yesterday_fc="$(to_int "$yesterday_fc")"
today_temp="$(to_int "$today_temp")"

# If still empty, stop safely
if [[ -z "$yesterday_fc" || -z "$today_temp" ]]; then
  echo "Could not parse yesterday_fc/today_temp from log. Check $LOG_FILE formatting."
  exit 1
fi

accuracy=$((yesterday_fc - today_temp))
echo "accuracy is $accuracy"

# -----------------------------
# 5) Accuracy range (fixed bash arithmetic conditions)
# -----------------------------
if (( accuracy >= -1 && accuracy <= 1 )); then
  accuracy_range="excellent"
elif (( accuracy >= -2 && accuracy <= 2 )); then
  accuracy_range="good"
elif (( accuracy >= -3 && accuracy <= 3 )); then
  accuracy_range="fair"
else
  accuracy_range="poor"
fi

echo "Forecast accuracy is $accuracy_range"

# -----------------------------
# 6) Append to history file (TSV)
# columns: year month day today_temp yesterday_fc accuracy accuracy_range
# -----------------------------
# Create header if file doesn't exist
if [[ ! -f "$HISTORY_FILE" ]]; then
  printf "year\tmonth\tday\ttoday_temp\tyesterday_fc\taccuracy\taccuracy_range\n" > "$HISTORY_FILE"
fi

printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
  "$year" "$month" "$day" "$today_temp" "$yesterday_fc" "$accuracy" "$accuracy_range" >> "$HISTORY_FILE"
