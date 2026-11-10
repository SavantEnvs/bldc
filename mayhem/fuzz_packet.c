/* Fuzz the VESC packet framing decoder (comm/packet.c, util/crc.c). */
#include <stdint.h>
#include <stddef.h>
#include <string.h>
#include "packet.h"

static unsigned int delivered;

static void send_func(unsigned char *data, unsigned int len) { (void)data; (void)len; }
static void process_func(unsigned char *data, unsigned int len) {
  /* Touch every delivered payload byte so ASan sees out-of-bounds reads. */
  volatile unsigned char sink = 0;
  for (unsigned int i = 0; i < len; i++) sink ^= data[i];
  delivered += len;
}

int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size) {
  if (size == 0) return -1;

  PACKET_STATE_t state;
  memset(&state, 0, sizeof(state));
  packet_init(send_func, process_func, &state);

  for (size_t i = 0; i < size; i++) {
    packet_process_byte(data[i], &state);
  }
  return 0;
}
