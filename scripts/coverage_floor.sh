#!/usr/bin/env bash
# fails when line coverage in an lcov report is below the given floor
# generated localizations are excluded: they come from the arb files, and
# testing them would measure the generator rather than this code
set -euo pipefail

report=${1:?usage: coverage_floor.sh <lcov.info> <floor>}
floor=${2:?usage: coverage_floor.sh <lcov.info> <floor>}

[ -f "$report" ] || { echo "no coverage report at $report" >&2; exit 1; }

read -r hit total < <(
  awk '
    /^SF:/  { skip = index($0, "/l10n/generated/") > 0 }
    /^DA:/  { if (!skip) { total++; if ($0 !~ /,0$/) hit++ } }
    END     { print hit + 0, total + 0 }
  ' "$report"
)

[ "$total" -gt 0 ] || { echo "coverage report is empty" >&2; exit 1; }

percent=$((hit * 100 / total))
echo "coverage: ${percent}% (${hit}/${total} lines), floor ${floor}%"
[ "$percent" -ge "$floor" ] || { echo "below the floor" >&2; exit 1; }
