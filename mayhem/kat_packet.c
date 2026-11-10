/* Known-answer probe for the VESC packet framing, CRC and buffer helpers. Built with normal flags. */
#include <stdio.h>
#include <string.h>
#include <stdint.h>
#include "packet.h"
#include "crc.h"
#include "buffer.h"

static unsigned char tx[PACKET_BUFFER_LEN];
static unsigned int tx_len;
static unsigned char rx[PACKET_BUFFER_LEN];
static unsigned int rx_len;
static unsigned int rx_count;

static void send_func(unsigned char *data, unsigned int len) {
  memcpy(tx, data, len);
  tx_len = len;
}

static void process_func(unsigned char *data, unsigned int len) {
  memcpy(rx, data, len);
  rx_len = len;
  rx_count++;
}

static void hex(const char *label, const unsigned char *d, unsigned int n) {
  printf("%s:", label);
  for (unsigned int i = 0; i < n; i++) printf(" %02x", d[i]);
  printf("\n");
}

int main(void) {
  unsigned char check[] = "123456789";
  printf("crc16 123456789: %04x\n", crc16(check, 9));

  PACKET_STATE_t st;
  packet_init(send_func, process_func, &st);

  unsigned char payload[] = { 0x04, 0x01, 0x02, 0x03 };
  packet_send_packet(payload, sizeof(payload), &st);
  hex("frame", tx, tx_len);

  unsigned char frame[PACKET_BUFFER_LEN];
  unsigned int frame_len = tx_len;
  memcpy(frame, tx, tx_len);

  /* Garbage in front of a valid frame must be skipped. */
  PACKET_STATE_t rxs;
  packet_init(send_func, process_func, &rxs);
  rx_count = 0;
  unsigned char junk[] = { 0x00, 0xff, 0x55 };
  for (unsigned int i = 0; i < sizeof(junk); i++) packet_process_byte(junk[i], &rxs);
  for (unsigned int i = 0; i < frame_len; i++) packet_process_byte(frame[i], &rxs);
  printf("decoded count: %u\n", rx_count);
  hex("decoded payload", rx, rx_len);

  /* A corrupted CRC must not be delivered. */
  packet_init(send_func, process_func, &rxs);
  rx_count = 0;
  frame[frame_len - 2] ^= 0x01;
  for (unsigned int i = 0; i < frame_len; i++) packet_process_byte(frame[i], &rxs);
  printf("corrupt count: %u\n", rx_count);

  /* A 300 byte payload uses the 16-bit length form. */
  unsigned char big[300];
  for (unsigned int i = 0; i < sizeof(big); i++) big[i] = (unsigned char)(i * 7);
  packet_init(send_func, process_func, &st);
  packet_send_packet(big, sizeof(big), &st);
  printf("big frame: len=%u start=%02x lenhi=%02x lenlo=%02x\n", tx_len, tx[0], tx[1], tx[2]);
  packet_init(send_func, process_func, &rxs);
  rx_count = 0;
  for (unsigned int i = 0; i < tx_len; i++) packet_process_byte(tx[i], &rxs);
  printf("big decoded: count=%u len=%u match=%d\n", rx_count, rx_len,
         rx_len == sizeof(big) && memcmp(rx, big, sizeof(big)) == 0);

  uint8_t buf[16];
  int32_t ind = 0;
  buffer_append_int32(buf, -123456, &ind);
  buffer_append_uint16(buf, 0xBEEF, &ind);
  buffer_append_float32_auto(buf, 12.5f, &ind);
  hex("buffer", buf, (unsigned int)ind);
  ind = 0;
  int32_t a = buffer_get_int32(buf, &ind);
  uint16_t b = buffer_get_uint16(buf, &ind);
  float c = buffer_get_float32_auto(buf, &ind);
  printf("buffer read: %d %u %g\n", (int)a, (unsigned)b, (double)c);
  return 0;
}
