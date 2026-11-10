#!/usr/bin/env bash
#
# mayhem/test.sh — runs the known-answer probes built by mayhem/build.sh and compares their output
# line by line against exact expected values. A missing or crashed probe fails every line it owes.
#
# IMPORTANT:
#  * Must assert BEHAVIOR/OUTPUT, not just exit status. The oracle has to check asserted values /
#    golden-output diffs / known-answer results — so a PATCH that "fixes" a bug by making the program
#    exit(0) (or any no-op) FAILS here. Running inputs and checking only "exit 0 / didn't crash" is
#    NOT a functional test (it's trivially reward-hackable) — use the project's real assertion suite.
#  * Do NOT build here — mayhem/build.sh already compiled the test suite (with the project's normal
#    flags). This script only RUNS the pre-built tests and reports counts. If the test runner is
#    missing, that's a build.sh bug — fail loudly rather than silently rebuilding.
#  * REQUIRED OUTPUT — a CTRF (https://ctrf.io) summary so Mayhem/the PATCH grader reads the counts:
#      - writes a CTRF JSON report to ${CTRF_REPORT:-$SRC/ctrf-report.json}, and
#      - prints a one-line `CTRF {...}` marker to stdout (same JSON, compact).
#    Only `results.summary` (with tests/passed/failed/pending/skipped/other) is required.
#    Use the emit_ctrf helper below; it computes tests = passed+failed+skipped and sets the exit
#    code (0 iff failed==0). Map your framework's output to passed/failed/skipped.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"   # build parallelism; env-overridable, falls back to nproc (use -j"$MAYHEM_JOBS")
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}


OUT="$SRC/build/mayhem"
passed=0
failed=0

# check <name> <expected> <actual>
check() {
  if [ "$2" == "$3" ]; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    echo "FAIL $1" >&2
    echo "  expected: $2" >&2
    echo "  actual:   $3" >&2
  fi
}

# run_probe <binary>: prints the binary's stdout, or nothing if it is missing or fails.
run_probe() {
  [ -x "$1" ] || { echo "missing probe $1" >&2; return 0; }
  "$1" 2>/dev/null || true
}

lbm_out=$(run_probe "$OUT/kat_lbm")
expect_lbm() { check "lbm: $1" "$1 => $2" "$(grep -F -x -- "$1 => $2" <<<"$lbm_out" || true)"; }
expect_lbm '(+ 1 2)' '3'
expect_lbm '(* 6 7)' '42'
expect_lbm "(map (lambda (x) (* x x)) '(1 2 3 4))" '(1 4 9 16)'
expect_lbm '(define fac (lambda (n) (if (= n 0) 1 (* n (fac (- n 1)))))) (fac 10)' '3628800'
expect_lbm '(str-merge "foo" "bar")' '"foobar"'
expect_lbm '(foldl + 0 (range 1 11))' '55'
expect_lbm '(let ((a 5) (b 7)) (list (+ a b) (- a b)))' '(12 -2)'
expect_lbm '(bufget-u8 (bufcreate 4) 2)' '0'
expect_lbm "(+ 1 'a)" 'type_error'
check "lbm: line count" "9" "$(wc -l <<<"$lbm_out" | tr -d ' ')"

pkt_out=$(run_probe "$OUT/kat_packet")
expect_pkt() { check "packet: $1" "$1$2" "$(grep -F -x -- "$1$2" <<<"$pkt_out" || true)"; }
expect_pkt 'crc16 123456789:' ' 31c3'
expect_pkt 'frame:' ' 02 04 04 01 02 03 ab c0 03'
expect_pkt 'decoded count:' ' 1'
expect_pkt 'decoded payload:' ' 04 01 02 03'
expect_pkt 'corrupt count:' ' 0'
expect_pkt 'big frame:' ' len=306 start=03 lenhi=01 lenlo=2c'
expect_pkt 'big decoded:' ' count=1 len=300 match=1'
expect_pkt 'buffer:' ' ff fe 1d c0 be ef 41 48 00 00'
expect_pkt 'buffer read:' ' -123456 48879 12.5'

fs_out=$(run_probe "$OUT/float_serialization" | tr -d '\r')
expect_fs() { check "float_serialization: $1" "$1" "$(grep -F -x -- "$1" <<<"$fs_out" | head -n 1 || true)"; }
expect_fs 'Test with subnormal number: 5e-39'
expect_fs 'Read typecast: 5e-39'
expect_fs 'Read buffer: 8.37747e-39'
check "float_serialization: line count" "7" "$(wc -l <<<"$fs_out" | tr -d ' ')"

emit_ctrf "mayhem-kat" "$passed" "$failed" 0
