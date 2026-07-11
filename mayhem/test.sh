#!/usr/bin/env bash
#
# tomlplusplus/mayhem/test.sh — RUN tomlplusplus' OWN Catch2 unit-test binary (built by
# mayhem/build.sh with normal flags) and emit a CTRF summary. exit 0 iff no test failed.
#
# PATCH-grade oracle: the suite is the project's real Catch2 test set, including the TOML conformance
# suites (conformance_burntsushi_{valid,invalid}, conformance_iarna_{valid,invalid}) plus the parsing_*
# / manipulating_* / formatters / path tests. They assert concrete parse RESULTS and serialized OUTPUT,
# so a no-op / "return 0" patch to the parser cannot pass. This script only RUNS the pre-built binary
# (Catch2 XML reporter for machine-readable counts); it never compiles.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

SRC="${SRC:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$SRC"

TEST_BIN="$SRC/mayhem-tests/unit_tests"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
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

if [ ! -x "$TEST_BIN" ]; then
  echo "missing $TEST_BIN — run mayhem/build.sh first" >&2
  emit_ctrf "catch2" 0 1 0; exit 2
fi

echo "=== running tomlplusplus Catch2 unit tests ==="
# Catch2 v2 XML reporter: <OverallResults successes=".." failures=".." expectedFailures=".."/> at the
# tail summarises assertions; we count PASS/FAIL at the TEST-CASE granularity from <OverallResults ...>
# closing each <TestCase>. Run with --durations no, all sections.
xml="$("$TEST_BIN" -r xml 2>/dev/null)"; rc=$?
# Also capture human-readable console output for the build log.
"$TEST_BIN" 2>&1 | tail -5 || true

# Parse the per-test-case results: Catch2 emits one <OverallResult success="true|false"/> per TestCase.
PASSED=0; FAILED=0
if [ -n "$xml" ]; then
  PASSED=$(printf '%s\n' "$xml" | grep -c '<OverallResult success="true"')
  FAILED=$(printf '%s\n' "$xml" | grep -c '<OverallResult success="false"')
fi

# Fallback: if XML produced nothing parseable, trust the exit code.
if [ "$(( PASSED + FAILED ))" -eq 0 ]; then
  echo "could not parse Catch2 XML output; using exit code $rc" >&2
  [ "$rc" -eq 0 ] && { emit_ctrf "catch2" 1 0 0; exit 0; }
  emit_ctrf "catch2" 0 1 0; exit 1
fi

emit_ctrf "catch2" "$PASSED" "$FAILED" 0
