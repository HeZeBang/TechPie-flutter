#ifndef TECHPIE_WATCH_CRYPTO_H
#define TECHPIE_WATCH_CRYPTO_H
#include <stddef.h>
#include <stdint.h>
int tp_public_key(const uint8_t private_key[32], uint8_t compressed[33]);
int tp_sm2_sign(const uint8_t private_key[32], const uint8_t *message, size_t length, uint8_t signature[64]);
int tp_sm2_verify(const uint8_t public_key[33], const uint8_t *message, size_t length, const uint8_t signature[64]);
void tp_sm3(const uint8_t *message, size_t length, uint8_t digest[32]);
// Row-major modules; returns side length, or zero on error. Capacity >= 177*177.
int tp_qr_encode(const uint8_t *data, size_t length, uint8_t *modules, size_t capacity);
#endif
