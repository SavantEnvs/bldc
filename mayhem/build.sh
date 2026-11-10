#!/usr/bin/env bash
#
# mayhem/build.sh: builds the fuzz targets (LispBM evaluator, LispBM flat-value decoder, VESC packet
# decoder) with sanitizers, plus the oracle probes and upstream's float_serialization test with normal flags.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# The base ENV already sets SANITIZER_FLAGS, so relaxations are appended here unconditionally. They are
# only meaningful with UBSan on, hence the guard on the flag rather than on the value.
RELAX=""
case "$SANITIZER_FLAGS" in *undefined*) RELAX="-fno-sanitize=function,alignment,pointer-overflow,nonnull-attribute" ;; esac

OUT="$SRC/build/mayhem"
LBM="$SRC/lispBM/lispBM"
rm -rf "$OUT"
mkdir -p "$OUT/lbm-san" "$OUT/lbm-test" "$OUT/pkt-san" "$OUT/pkt-test"

# Source and include lists come from LispBM's own makefile fragment.
LBM_SRC=$(make -s -f <(printf 'include $(LISPBM)/lispbm.mk\nprint-%%:\n\t@echo $($*)\n') LISPBM="$LBM" print-LISPBM_SRC)
LBM_INC=$(make -s -f <(printf 'include $(LISPBM)/lispbm.mk\nprint-%%:\n\t@echo $($*)\n') LISPBM="$LBM" print-LISPBM_INC)
PLATFORM_SRC="$LBM/platform/linux/src/platform_mutex.c $LBM/platform/linux/src/platform_timestamp.c $LBM/platform/linux/src/platform_thread.c"
PLATFORM_INC="-I$LBM/platform/linux/include"
LBM_DEFS="-DLBM64 -DLBM_SINGLE_THREADED -DFULL_RTS_LIB -DLBM_USE_DYN_FUNS -DLBM_USE_DYN_MACROS -DLBM_USE_DYN_LOOPS -DLBM_USE_DYN_ARRAYS"

# compile_all <outdir> <flags...> -- <sources...>: one object per source, in parallel.
compile_all() {
  local outdir="$1"; shift
  local flags=()
  while [ "$1" != "--" ]; do flags+=("$1"); shift; done
  shift
  printf '%s\n' "$@" | xargs -P "$MAYHEM_JOBS" -I{} bash -c '
    src="$1"; outdir="$2"; shift 2
    obj="$outdir/$(echo "${src#$SRC/}" | tr "/" "_").o"
    '"$CC"' "$@" -c "$src" -o "$obj"
  ' _ {} "$outdir" "${flags[@]}"
}

# 1) Sanitized + SanCov-instrumented LispBM and packet code (fuzzed code).
FUZZ_CFLAGS=($SANITIZER_FLAGS $DEBUG_FLAGS $RELAX -fsanitize=fuzzer-no-link -O1 -std=gnu11 -w)
compile_all "$OUT/lbm-san" "${FUZZ_CFLAGS[@]}" $LBM_DEFS $LBM_INC $PLATFORM_INC -- $LBM_SRC $PLATFORM_SRC
compile_all "$OUT/pkt-san" "${FUZZ_CFLAGS[@]}" -DNO_STM32 -I"$SRC/comm" -I"$SRC/util" -- \
  "$SRC/comm/packet.c" "$SRC/util/crc.c" "$SRC/util/buffer.c"

$CC $SANITIZER_FLAGS $DEBUG_FLAGS -x c -c "$STANDALONE_FUZZ_MAIN" -o "$OUT/standalone_main.o"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c "$SRC/mayhem/lsan_off.cc" -o "$OUT/lsan_off.o"

LBM_OBJS=("$OUT"/lbm-san/*.o)
PKT_OBJS=("$OUT"/pkt-san/*.o)


# lbm harnesses
for t in fuzz_lbm_eval fuzz_lbm_flat; do
  $CC "${FUZZ_CFLAGS[@]}" $LBM_DEFS $LBM_INC $PLATFORM_INC -I"$SRC/mayhem" \
      -c "$SRC/mayhem/$t.c" -o "$OUT/$t.o"
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$OUT/$t.o" "${LBM_OBJS[@]}" "$OUT/lsan_off.o" \
      -lm -lpthread -o "/mayhem/$t"
  $CC $SANITIZER_FLAGS $DEBUG_FLAGS "$OUT/standalone_main.o" "$OUT/$t.o" "${LBM_OBJS[@]}" "$OUT/lsan_off.o" \
      -lm -lpthread -o "/mayhem/$t-standalone"
done

# packet harness
$CC "${FUZZ_CFLAGS[@]}" -DNO_STM32 -I"$SRC/comm" -I"$SRC/util" \
    -c "$SRC/mayhem/fuzz_packet.c" -o "$OUT/fuzz_packet.o"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$OUT/fuzz_packet.o" "${PKT_OBJS[@]}" "$OUT/lsan_off.o" \
    -lm -o /mayhem/fuzz_packet
$CC $SANITIZER_FLAGS $DEBUG_FLAGS "$OUT/standalone_main.o" "$OUT/fuzz_packet.o" "${PKT_OBJS[@]}" "$OUT/lsan_off.o" \
    -lm -o /mayhem/fuzz_packet-standalone

# 2) Oracle probes and upstream's float_serialization test: normal flags, no sanitizers.
TEST_CFLAGS=(-O2 -std=gnu11 -w $COVERAGE_FLAGS)
compile_all "$OUT/lbm-test" "${TEST_CFLAGS[@]}" $LBM_DEFS $LBM_INC $PLATFORM_INC -- $LBM_SRC $PLATFORM_SRC
$CC "${TEST_CFLAGS[@]}" $LBM_DEFS $LBM_INC $PLATFORM_INC -I"$SRC/mayhem" \
    "$SRC/mayhem/kat_lbm.c" "$OUT"/lbm-test/*.o $COVERAGE_FLAGS -lm -lpthread -o "$OUT/kat_lbm"

$CC "${TEST_CFLAGS[@]}" -DNO_STM32 -I"$SRC/comm" -I"$SRC/util" \
    "$SRC/mayhem/kat_packet.c" "$SRC/comm/packet.c" "$SRC/util/crc.c" "$SRC/util/buffer.c" \
    $COVERAGE_FLAGS -lm -o "$OUT/kat_packet"

$CC "${TEST_CFLAGS[@]}" -DNO_STM32 -I"$SRC/util" \
    "$SRC/tests/float_serialization/main.c" "$SRC/util/buffer.c" $COVERAGE_FLAGS -lm \
    -o "$OUT/float_serialization"
