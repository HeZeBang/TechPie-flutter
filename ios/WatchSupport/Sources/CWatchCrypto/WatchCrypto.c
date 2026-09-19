#include "WatchCrypto.h"
#include <gmssl/sm2.h>
#include <gmssl/mem.h>
#include "qrcodegen.h"
#include <string.h>

static int load_key(SM2_KEY *key, const uint8_t bytes[32]) {
  sm2_z256_t upper;
  memset(key, 0, sizeof(*key));
  sm2_z256_from_bytes(key->private_key, bytes);
  sm2_z256_sub(upper, sm2_z256_order(), sm2_z256_one());
  if (sm2_z256_is_zero(key->private_key) || sm2_z256_cmp(key->private_key, upper) >= 0) return 0;
  sm2_z256_point_mul_generator(&key->public_key, key->private_key);
  return 1;
}

// The only key helper required by upstream sm2_sign.c; no key serialization APIs.
int sm2_key_set_public_key(SM2_KEY *key, const SM2_Z256_POINT *public_key) {
  memset(key, 0, sizeof(*key));
  if (!sm2_z256_point_is_on_curve(public_key)) return -1;
  key->public_key = *public_key;
  return 1;
}

int tp_public_key(const uint8_t private_key[32], uint8_t compressed[33]) {
  SM2_KEY key;
  int ok = load_key(&key, private_key);
  if (ok) {
    uint8_t xy[64];
    sm2_z256_point_to_bytes(&key.public_key, xy);
    compressed[0] = (xy[63] & 1) ? 3 : 2;
    memcpy(compressed + 1, xy, 32);
  }
  gmssl_secure_clear(&key, sizeof(key));
  return ok;
}

static void digest_message(const SM2_KEY *key, const uint8_t *message, size_t length, uint8_t digest[32]) {
  uint8_t z[32];
  SM3_CTX context;
  sm2_compute_z(z, &key->public_key, SM2_DEFAULT_ID, SM2_DEFAULT_ID_LENGTH);
  sm3_init(&context);
  sm3_update(&context, z, sizeof(z));
  sm3_update(&context, message, length);
  sm3_finish(&context, digest);
  gmssl_secure_clear(&context, sizeof(context));
}

int tp_sm2_sign(const uint8_t private_key[32], const uint8_t *message, size_t length, uint8_t signature[64]) {
  SM2_KEY key;
  SM2_SIGNATURE sig;
  uint8_t digest[32];
  int ok = load_key(&key, private_key);
  if (ok) {
    digest_message(&key, message, length, digest);
    ok = sm2_do_sign(&key, digest, &sig) == 1;
    if (ok) { memcpy(signature, sig.r, 32); memcpy(signature + 32, sig.s, 32); }
  }
  gmssl_secure_clear(&key, sizeof(key));
  gmssl_secure_clear(&sig, sizeof(sig));
  gmssl_secure_clear(digest, sizeof(digest));
  return ok;
}

int tp_sm2_verify(const uint8_t public_key[33], const uint8_t *message, size_t length, const uint8_t signature[64]) {
  SM2_KEY key = {0};
  SM2_SIGNATURE sig;
  uint8_t digest[32];
  if (sm2_z256_point_from_octets(&key.public_key, public_key, 33) != 1) return 0;
  memcpy(sig.r, signature, 32); memcpy(sig.s, signature + 32, 32);
  digest_message(&key, message, length, digest);
  return sm2_do_verify(&key, digest, &sig) == 1;
}

void tp_sm3(const uint8_t *message, size_t length, uint8_t digest[32]) {
  SM3_CTX context;
  sm3_init(&context);
  sm3_update(&context, message, length);
  sm3_finish(&context, digest);
  gmssl_secure_clear(&context, sizeof(context));
}

int tp_qr_encode(const uint8_t *data, size_t length, uint8_t *modules, size_t capacity) {
  uint8_t buffer[qrcodegen_BUFFER_LEN_MAX], qr[qrcodegen_BUFFER_LEN_MAX];
  if (length > sizeof(buffer)) return 0;
  memcpy(buffer, data, length);
  if (!qrcodegen_encodeBinary(buffer, length, qr, qrcodegen_Ecc_LOW, 1, 40, qrcodegen_Mask_AUTO, false)) return 0;
  int side = qrcodegen_getSize(qr);
  if ((size_t)(side * side) > capacity) return 0;
  for (int y = 0; y < side; y++) for (int x = 0; x < side; x++) modules[y * side + x] = qrcodegen_getModule(qr, x, y);
  gmssl_secure_clear(buffer, sizeof(buffer));
  return side;
}
