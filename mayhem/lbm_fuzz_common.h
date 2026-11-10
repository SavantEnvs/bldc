/* Shared single-threaded LispBM bring-up for the fuzz harnesses and the oracle probe. */
#ifndef LBM_FUZZ_COMMON_H
#define LBM_FUZZ_COMMON_H

#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>

#include "lispbm.h"
#include "lbm_flat_value.h"
#include "lbm_channel.h"
#include "lbm_c_interop.h"
#include "lbm_image.h"
#include "extensions/array_extensions.h"
#include "extensions/string_extensions.h"
#include "extensions/math_extensions.h"
#include "extensions/set_extensions.h"
#include "extensions/crypto_extensions.h"
#include "extensions/pattern_extensions.h"
#include "extensions/lbm_dyn_lib.h"

#define FUZZ_HEAP_SIZE      4096
#define FUZZ_GC_STACK       256
#define FUZZ_PRINT_STACK    256
#define FUZZ_EXT_STORAGE    512

static lbm_cons_t      fuzz_heap[FUZZ_HEAP_SIZE];
static lbm_uint        fuzz_memory[LBM_MEMORY_SIZE_10K];
static lbm_uint        fuzz_bitmap[LBM_MEMORY_BITMAP_SIZE_10K];
static lbm_extension_t fuzz_extensions[FUZZ_EXT_STORAGE];

#define FUZZ_IMAGE_BYTES (128 * 1024)
static uint32_t fuzz_image[FUZZ_IMAGE_BYTES / sizeof(uint32_t)];

static bool fuzz_image_write(uint32_t w, int32_t ix, bool is_const_heap) {
  (void)is_const_heap;
  fuzz_image[ix] = w;
  return true;
}

static bool fuzz_dynamic_load(const char *sym, const char **code) {
  return lbm_dyn_lib_find(sym, code);
}

static void fuzz_sleep(uint32_t us) { (void)us; }

static bool fuzz_lbm_start(void (*done_cb)(eval_context_t *)) {
  if (!lbm_init(fuzz_heap, FUZZ_HEAP_SIZE,
                fuzz_memory, LBM_MEMORY_SIZE_10K,
                fuzz_bitmap, LBM_MEMORY_BITMAP_SIZE_10K,
                FUZZ_GC_STACK, FUZZ_PRINT_STACK,
                fuzz_extensions, FUZZ_EXT_STORAGE)) {
    return false;
  }
  if (!lbm_eval_init_events(20)) return false;
  memset(fuzz_image, 0, sizeof(fuzz_image));
  lbm_image_init(fuzz_image, FUZZ_IMAGE_BYTES / sizeof(uint32_t), fuzz_image_write);
  lbm_image_create("fuzz");
  if (!lbm_image_boot()) return false;
  lbm_set_ctx_done_callback(done_cb);
  lbm_set_usleep_callback(fuzz_sleep);
  lbm_set_dynamic_load_callback(fuzz_dynamic_load);

  lbm_array_extensions_init();
  lbm_string_extensions_init();
  lbm_math_extensions_init();
  lbm_set_extensions_init();
  lbm_pattern_extensions_init();
  lbm_crypto_extensions_init();
  lbm_dyn_lib_init();
  lbm_add_eval_symbols();
  return true;
}

#endif
