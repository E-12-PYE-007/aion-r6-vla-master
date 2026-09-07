#!/bin/bash
# Usage: ./tegra_bench.sh <label> <duration_seconds>
# Creates module_benchmarks/<label>/, logs tegrastats there for the given
# duration, then parses it into results.csv in that same folder.

set -e

LABEL="${1:?Usage: $0 <label> <duration_seconds>}"
DURATION="${2:?Usage: $0 <label> <duration_seconds>}"

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTDIR="$DIR/$LABEL"
mkdir -p "$OUTDIR"

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOGFILE="$OUTDIR/${LABEL}_${TIMESTAMP}.log"

echo "Logging tegrastats for ${DURATION}s (label: ${LABEL})..."
timeout "$DURATION" tegrastats --interval 500 --logfile "$LOGFILE" || true

echo "Done. Log: $LOGFILE"
python3 "$DIR/parse_tegrastats.py" "$LOGFILE" --label "$LABEL" --csv "$OUTDIR/results.csv"
