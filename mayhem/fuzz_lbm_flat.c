/* Fuzz the LispBM flat-value deserializer (lbm_flat_value.c) and print the resulting value. */
#include <stdlib.h>
#include "lbm_fuzz_common.h"
#include "print.h"

#define MAX_FLAT_LEN 2048

static void done_cb(eval_context_t *ctx) { (void)ctx; }

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  if (size == 0 || size > MAX_FLAT_LEN) return -1;
  if (!fuzz_lbm_start(done_cb)) return -1;

  uint8_t buf[MAX_FLAT_LEN];
  memcpy(buf, data, size);

  lbm_flat_value_t fv;
  fv.buf = buf;
  fv.buf_size = size;
  fv.buf_pos = 0;

  lbm_value v;
  if (lbm_unflatten_value(&fv, &v)) {
    char out[512];
    lbm_print_value(out, sizeof(out), v);
  }
  return 0;
}
