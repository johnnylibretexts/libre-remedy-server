#!/usr/bin/env bash
set -u

ROOT="${1:-tools/corpus_annotations/v1}"
RESULTS="${2:-tools/corpus_annotations/v1/behavioral_results.jsonl}"
DB="${3:-/tmp/remedy-quality-experiments.db}"
JUDGE_RESULTS="${4:-${ROOT}/judge_results.jsonl}"
PY="${VENV_PYTHON:-./.venv/bin/python}"
RUN_ROOT="$ROOT"

if [ ! -d "$ROOT" ]; then
  printf 'ERR: root directory not found: %s\n' "$ROOT"
  exit 1
fi
if [ ! -f "$RESULTS" ]; then
  RESULTS="$ROOT/behavioral_results.jsonl"
fi
if [ ! -f "$DB" ]; then
  DB="/tmp/remedy-quality-experiments.db"
fi

printf '\n== Quality layer audit: v2 docs scope ==\n'
printf 'root=%s\nresults=%s\n\n' "$ROOT" "$RESULTS"

run_cmd() {
  local label="$1"
  shift
  printf '%s\n' "$label"
  local output
  if ! output="$("$@" 2>/tmp/qla.err)"; then
    printf 'ERR: %s failed\n' "$label"
    if [[ -n "${output:-}" ]]; then
      printf '%s\n' "$output"
    fi
    if [[ -s /tmp/qla.err ]]; then
      cat /tmp/qla.err
    fi
    return 1
  fi
  printf '%s\n\n' "$output"
  return 0
}

status=0

run_cmd "1) Corpus coverage" \
  "$PY" tools/annotate_corpus.py coverage --root "$ROOT" --json || status=1

run_cmd "2) Snapshot gate" \
  "$PY" tools/verify_corpus_snapshots.py check --root "$ROOT" --json || status=1

run_cmd "3) Behavioral corpus gate" \
  "$PY" tools/verify_behavioral_corpus.py check --root "$ROOT" --results "$RESULTS" --json || status=1

calibration_cmd=( "$PY" tools/calibrate_judges.py calibrate --root "$ROOT" --store "$DB" --dry-run --enforce-readiness --json )
if [ -f "$JUDGE_RESULTS" ]; then
  calibration_cmd+=( --judge-results "$JUDGE_RESULTS" )
fi

run_cmd "4) Calibration readiness (dry-run)" \
  "${calibration_cmd[@]}" || status=1

run_cmd "5) Quality coverage" \
  "$PY" tools/quality_coverage.py check --threshold 70 || status=1

if [ "$status" -eq 0 ]; then
  printf '== Done ==\n'
else
  printf '== Done with failures ==\n'
fi

printf '\n== Artifact inventory ==\n'
python_count=$(find "$ROOT/annotations" -maxdepth 2 -type f -name '*.json' 2>/dev/null | wc -l)
snapshot_count=$(find "$ROOT/snapshots" -maxdepth 2 -type f -name '*.json' 2>/dev/null | wc -l)
if [ -f "$RESULTS" ]; then
  behavioral_count=$(wc -l < "$RESULTS")
else
  behavioral_count="missing"
fi
printf 'annotation_rows=%s\n' "$python_count"
printf 'snapshot_rows=%s\n' "$snapshot_count"
printf 'behavioral_rows=%s\n' "$behavioral_count"

exit "$status"
