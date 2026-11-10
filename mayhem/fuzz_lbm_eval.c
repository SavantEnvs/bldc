/* Fuzz the LispBM reader + evaluator (tokpar.c, eval_cps.c, heap, GC, extensions) with program text. */
#include <stdlib.h>
#include "lbm_fuzz_common.h"

#define MAX_PROGRAM_LEN 4096
#define STEP_CHUNK      100
#define MAX_CHUNKS      2000

static bool program_done;

static void done_cb(eval_context_t *ctx) { (void)ctx; program_done = true; }

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  if (size == 0 || size > MAX_PROGRAM_LEN) return -1;
  if (memchr(data, 0, size) != NULL) return -1;

  char program[MAX_PROGRAM_LEN + 1];
  memcpy(program, data, size);
  program[size] = '\0';

  program_done = false;
  if (!fuzz_lbm_start(done_cb)) return -1;

  lbm_string_channel_state_t state;
  lbm_char_channel_t chan;
  lbm_create_string_char_channel(&state, &chan, program);
  if (lbm_load_and_eval_program(&chan, NULL) < 0) return 0;

  for (int i = 0; i < MAX_CHUNKS && !program_done; i++) {
    lbm_eval_step(STEP_CHUNK);
  }
  return 0;
}
