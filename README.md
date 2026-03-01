# Weather Bash ETL Project

This project fetches weather data from wttr.in using Bash, logs it,
computes forecast accuracy, and stores historical results.

## Features

- Fetches current & forecast temperature
- Parses and logs as structured TSV
- Computes forecast accuracy vs observed
- Runs automatically via cron
- Easily extendable

## Usage

```bash
chmod +x rx_poc.sh
./rx_poc.sh
