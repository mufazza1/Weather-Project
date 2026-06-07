# Weather Bash ETL Project

A small, dependency-light **Bash ETL pipeline** that measures how accurate weather
forecasts are. Each day it fetches the weather for a city from
[wttr.in](https://wttr.in), records today's *observed* temperature alongside the
*forecast for tomorrow*, and — once it has two days of data — scores yesterday's
forecast against today's reality.

```
fetch (wttr.in JSON)  ->  record reading  ->  compute accuracy  ->  store history  ->  weekly report
```

## How it works

There are two data files (tab-separated, created automatically):

| File | Columns | Purpose |
|------|---------|---------|
| `weather_readings.tsv` | `date`, `obs_temp`, `fc_tomorrow` | One raw reading per day: what it actually was, and what was forecast for the next day. |
| `historical_fc_accuracy.tsv` | `date`, `obs_temp`, `forecast`, `error`, `rating` | The scored result for each day once it can be compared. |

The **error** is `forecast − observed` (in °C), where `forecast` is the value that
was predicted *yesterday for today*. The **rating** is based on the absolute error:

| Absolute error | Rating |
|----------------|-----------|
| ≤ 1 °C | `excellent` |
| ≤ 2 °C | `good` |
| ≤ 3 °C | `fair` |
| > 3 °C | `poor` |

## Requirements

- **Bash** 4+
- **curl**, **awk**, **grep**, **coreutils** (`date`, `cut`, `tail`, …) — standard on Linux/macOS and Git Bash on Windows.
- **jq** *(optional)* — if present it is used for JSON parsing; otherwise a pure-`awk` fallback is used. No install required either way.

## Usage

```bash
chmod +x rx_poc.sh weekly_stats.sh run_tests.sh

./rx_poc.sh        # fetch today's data, record it, score yesterday's forecast
./weekly_stats.sh  # print a report over the last 7 scored days
./weekly_stats.sh 30   # ...or over the last 30
```

You need to run `rx_poc.sh` on **two different days** before any accuracy is scored
(day one only has a forecast; day two can compare it to reality).

## Configuration

All settings can be overridden with environment variables — no need to edit the scripts:

| Variable | Default | Description |
|----------|---------|-------------|
| `CITY` | `Casablanca` | City to query on wttr.in. |
| `TZ_NAME` | `Africa/Casablanca` | Timezone used to compute "today"/"tomorrow". |
| `DATA_DIR` | script directory | Where the `.tsv` files are stored. |
| `CURL_TIMEOUT` | `20` | Per-request timeout (seconds). |
| `CURL_RETRIES` | `2` | Number of curl retries on failure. |

Example:

```bash
CITY="London" TZ_NAME="Europe/London" DATA_DIR="$HOME/weather-data" ./rx_poc.sh
```

## Scheduling (run it daily)

**Linux/macOS — cron.** Run every day at 08:00:

```cron
0 8 * * *  /full/path/to/Weather-Project/rx_poc.sh >> /full/path/to/Weather-Project/rx_poc.log 2>&1
```

**Windows — Task Scheduler.** Create a daily task whose action runs Git Bash:

```
Program:   C:\Program Files\Git\bin\bash.exe
Arguments: -lc "/c/Users/you/Weather-Project/rx_poc.sh"
```

## Testing

The project ships with an offline test suite that uses a saved API response
(`tests/fixtures/wttr_sample.json`), so it needs no network:

```bash
./run_tests.sh
```

It covers the helper functions, JSON extraction (both the `jq` and `awk` paths),
the end-to-end ETL (including same-day idempotency), and the weekly report.

## Project layout

```
.
├── rx_poc.sh                     # main daily ETL
├── weekly_stats.sh               # accuracy report
├── lib.sh                        # shared helpers (logging, fetch, JSON, dates)
├── run_tests.sh                  # offline test suite
├── tests/fixtures/wttr_sample.json  # saved wttr.in response for tests
├── .gitignore
└── README.md
```

## Notes & limitations

- wttr.in returns roughly a **3-day** forecast window. Requesting a forecast for a
  date outside that window fails fast with a clear error.
- Accuracy assumes **one run per day on consecutive days**. Re-running on the same
  day refreshes that day's reading instead of duplicating it; gaps between days are
  not interpolated.
- If the noon forecast for a day is unavailable, the script falls back to that day's
  average temperature.
