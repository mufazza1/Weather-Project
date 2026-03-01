#!/usr/bin/env bash
set -euo pipefail

HISTORY_FILE="historical_fc_accuracy.tsv"

if [[ ! -f "$HISTORY_FILE" ]]; then
  echo "No historical data found."
  exit 1
fi

# Skip header and analyze last 7 entries
data="$(tail -n 7 "$HISTORY_FILE" | awk 'NR>1')"

if [[ -z "$data" ]]; then
  echo "Not enough data for weekly stats."
  exit 0
fi

days="$(echo "$data" | wc -l)"

avg_accuracy="$(echo "$data" | awk '{sum+=$6} END { if (NR>0) print sum/NR; else print 0 }')"

best_accuracy="$(echo "$data" | awk 'NR==1 || $6 < min {min=$6} END {print min}')"

worst_accuracy="$(echo "$data" | awk 'NR==1 || $6 > max {max=$6} END {print max}')"

excellent="$(echo "$data" | grep -c excellent || true)"
good="$(echo "$data" | grep -c good || true)"
fair="$(echo "$data" | grep -c fair || true)"
poor="$(echo "$data" | grep -c poor || true)"

echo "Weekly Forecast Accuracy Report"
echo "--------------------------------"
echo "Days analyzed: $days"
echo "Average accuracy: $avg_accuracy °C"
echo "Best accuracy: $best_accuracy °C"
echo "Worst accuracy: $worst_accuracy °C"
echo ""
echo "Accuracy distribution:"
echo "  Excellent: $excellent"
echo "  Good:      $good"
echo "  Fair:      $fair"
echo "  Poor:      $poor"
