#!/usr/bin/env bash
#
# tomlplusplus/mayhem/build.sh — build marzer/tomlplusplus' single OSS-Fuzz harness as a sanitized
# libFuzzer target (+ a standalone reproducer), and build the project's own Catch2 unit-test binary
# (with NORMAL flags) for mayhem/test.sh to RUN.
#
# Fuzzed surface (mayhem/harnesses/toml_fuzzer.cpp, vendored from upstream fuzzing/toml_fuzzer.cpp):
#   toml_fuzzer — parses attacker-controlled TOML text via toml::parse(), then runs the parsed table
#                 through the JSON/YAML/TOML formatters. toml++ is HEADER-ONLY, so we compile the
#                 harness directly against include/toml++/toml.hpp with $SANITIZER_FLAGS — the whole
#                 parser+serializer is instrumented (no separate library to build).
#
# Build contract comes from the org base ENV: CC/CXX/SANITIZER_FLAGS/LIB_FUZZING_ENGINE/
# STANDALONE_FUZZ_MAIN/SRC/OUT. Output binaries land in /mayhem.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

# `=` (not `:=`) for SANITIZER_FLAGS so an explicit empty --build-arg builds with NO sanitizers.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer -g}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CXX:=clang++}"
: "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${STANDALONE_FUZZ_MAIN:=}"
: "${OUT:=/mayhem}"
export SANITIZER_FLAGS DEBUG_FLAGS CXX LIB_FUZZING_ENGINE OUT

# Resolve the repo root (the build context lands at /mayhem; SRC may also be set by the base).
SRC="${SRC:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$SRC"

HARNESS="$SRC/mayhem/harnesses/toml_fuzzer.cpp"
# Header-only: include/toml++/toml.hpp resolves <toml++/toml.hpp>.
INC="-I$SRC/include"
# -DNDEBUG mirrors upstream fuzzing/CMakeLists.txt (no asserts in the fuzzed build).
CXXSTD="-std=c++17 -DNDEBUG"

echo "=== building toml_fuzzer (libFuzzer) ==="
$CXX $CXXSTD $SANITIZER_FLAGS $DEBUG_FLAGS $INC \
    "$HARNESS" $LIB_FUZZING_ENGINE \
    -o "$OUT/toml_fuzzer"

echo "=== building toml_fuzzer-standalone (single-input reproducer) ==="
# $STANDALONE_FUZZ_MAIN provides a main() that reads one input file and calls LLVMFuzzerTestOneInput
# once (no libFuzzer runtime). The base image ships it; fall back to a libFuzzer build w/ -runs flag
# only if it is genuinely absent.
if [ -n "$STANDALONE_FUZZ_MAIN" ] && [ -f "$STANDALONE_FUZZ_MAIN" ]; then
    # Compile the C driver as C (-x c) so its LLVMFuzzerTestOneInput reference keeps C linkage and
    # links against the harness's extern "C" definition; clang++ would otherwise C++-mangle it.
    STANDALONE_OBJ="$SRC/mayhem-tests/standalone_main.o"
    mkdir -p "$SRC/mayhem-tests"
    "$CXX" $SANITIZER_FLAGS $DEBUG_FLAGS -x c -std=c11 -c "$STANDALONE_FUZZ_MAIN" -o "$STANDALONE_OBJ"
    $CXX $CXXSTD $SANITIZER_FLAGS $DEBUG_FLAGS $INC \
        "$HARNESS" "$STANDALONE_OBJ" \
        -o "$OUT/toml_fuzzer-standalone"
else
    echo "WARNING: STANDALONE_FUZZ_MAIN unset/missing — building standalone with libFuzzer engine" >&2
    $CXX $CXXSTD $SANITIZER_FLAGS $DEBUG_FLAGS $INC \
        "$HARNESS" $LIB_FUZZING_ENGINE \
        -o "$OUT/toml_fuzzer-standalone"
fi

# ── Build tomlplusplus' OWN Catch2 unit-test binary with NORMAL flags (no sanitizers) so that
#    mayhem/test.sh only RUNS it. Mirrors upstream fuzzing/build.sh: a single self-contained binary
#    compiled against the vendored Catch2 (vendor/catch.hpp) + the bundled conformance test data. ──
echo "=== building tomlplusplus unit-test binary (normal flags) ==="
TEST_BIN="$SRC/mayhem-tests/unit_tests"
mkdir -p "$SRC/mayhem-tests"
env -u CFLAGS -u CXXFLAGS -u SANITIZER_FLAGS \
  "$CXX" -std=c++17 -O1 -DUSE_VENDORED_LIBS=1 \
    -I"$SRC/include" -I"$SRC/tests" \
    "$SRC"/tests/at_path.cpp \
    "$SRC"/tests/conformance_burntsushi_invalid.cpp \
    "$SRC"/tests/conformance_burntsushi_valid.cpp \
    "$SRC"/tests/conformance_iarna_invalid.cpp \
    "$SRC"/tests/conformance_iarna_valid.cpp \
    "$SRC"/tests/formatters.cpp \
    "$SRC"/tests/for_each.cpp \
    "$SRC"/tests/impl_toml.cpp \
    "$SRC"/tests/main.cpp \
    "$SRC"/tests/manipulating_arrays.cpp \
    "$SRC"/tests/manipulating_parse_result.cpp \
    "$SRC"/tests/manipulating_tables.cpp \
    "$SRC"/tests/manipulating_values.cpp \
    "$SRC"/tests/parsing_arrays.cpp \
    "$SRC"/tests/parsing_booleans.cpp \
    "$SRC"/tests/parsing_comments.cpp \
    "$SRC"/tests/parsing_dates_and_times.cpp \
    "$SRC"/tests/parsing_floats.cpp \
    "$SRC"/tests/parsing_integers.cpp \
    "$SRC"/tests/parsing_key_value_pairs.cpp \
    "$SRC"/tests/parsing_spec_example.cpp \
    "$SRC"/tests/parsing_strings.cpp \
    "$SRC"/tests/parsing_tables.cpp \
    "$SRC"/tests/path.cpp \
    "$SRC"/tests/tests.cpp \
    "$SRC"/tests/user_feedback.cpp \
    "$SRC"/tests/using_iterators.cpp \
    "$SRC"/tests/visit.cpp \
    "$SRC"/tests/windows_compat.cpp \
    -o "$TEST_BIN" \
    -pthread
echo "built unit-test binary -> $TEST_BIN"

echo "=== build.sh complete ==="
ls -la "$OUT/toml_fuzzer" "$OUT/toml_fuzzer-standalone" 2>&1 || true
