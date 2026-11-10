/* Known-answer probe for the LispBM evaluator: evaluates fixed programs and prints the results. Normal flags. */
#include "lbm_fuzz_common.h"
#include "print.h"

static char result[256];
static bool finished;

static void done_cb(eval_context_t *ctx) {
  lbm_print_value(result, sizeof(result), ctx->r);
  finished = true;
}

static void eval(const char *program) {
  static lbm_string_channel_state_t state;
  static lbm_char_channel_t chan;
  static char text[1024];
  strncpy(text, program, sizeof(text) - 1);
  finished = false;
  result[0] = '\0';
  if (!fuzz_lbm_start(done_cb)) {
    printf("%s => INIT FAILED\n", program);
    return;
  }
  lbm_create_string_char_channel(&state, &chan, text);
  if (lbm_load_and_eval_program(&chan, NULL) < 0) {
    printf("%s => SPAWN FAILED\n", program);
    return;
  }
  for (int i = 0; i < 1000000 && !finished; i++) lbm_eval_step(1);
  printf("%s => %s\n", program, finished ? result : "UNFINISHED");
}

int main(void) {
  eval("(+ 1 2)");
  eval("(* 6 7)");
  eval("(map (lambda (x) (* x x)) '(1 2 3 4))");
  eval("(define fac (lambda (n) (if (= n 0) 1 (* n (fac (- n 1)))))) (fac 10)");
  eval("(str-merge \"foo\" \"bar\")");
  eval("(foldl + 0 (range 1 11))");
  eval("(let ((a 5) (b 7)) (list (+ a b) (- a b)))");
  eval("(bufget-u8 (bufcreate 4) 2)");
  eval("(+ 1 'a)");
  return 0;
}
