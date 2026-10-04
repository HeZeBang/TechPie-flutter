// Packet I/O for the eCard bind tunnel's DNS responder.
//
// The interface the VPN extension creates is handed over as a file descriptor,
// and it is not a file: it is a non-seekable character device. Reading it from
// ArkTS is the one link of this tunnel that has no precedent — the OHOS VPN
// guide's own sample and the Tailscale port both do their packet I/O in native
// code — so the reads and writes happen here and everything else (DNS parsing,
// the reply, forwarding) stays in ArkTS where it can be read as one piece.
//
// Exposes three calls:
//   startReading(fd, onPacket, onError)  one packet per call, on the JS thread
//   writePacket(fd, data, length)        0, or -errno
//   stopReading()                        ends the loop; the fd outlives it

#include <napi/native_api.h>

#include <atomic>
#include <cerrno>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <thread>
#include <unistd.h>

#ifndef ECARDBIND_SOURCE_SHA256
#error "ECARDBIND_SOURCE_SHA256 is missing — build through ohos/scripts/build-ecardbind-reader.sh."
#endif

// The .so this compiles to is committed (ohos/entry/libs/arm64-v8a/), not
// rebuilt by hvigor, so an ordinary build would never notice a source edit that
// was not compiled. The build script passes a digest of everything in this
// directory in as ECARDBIND_SOURCE_SHA256; the text below is where it lands, and
// test/ecard_bind_reader_artifact_test.dart is what reads it back and compares
// it against the source tree. Exported and marked used so no linker or strip
// pass can drop it.
extern "C" __attribute__((visibility("default"), used))
const char kTechPieEcardBindSourceDigest[] =
    "TECHPIE-ECARDBIND-SRC-SHA256=" ECARDBIND_SOURCE_SHA256;

namespace {

constexpr int kPacketSize = 2048;

std::thread g_reader;
std::atomic<bool> g_reading{false};
napi_threadsafe_function g_on_packet = nullptr;
napi_threadsafe_function g_on_error = nullptr;

struct Packet {
  uint8_t* bytes;
  int32_t length;
};

/** Runs on the JS thread: hands one packet to ArkTS, then frees it. */
void DeliverPacket(napi_env env, napi_value js_callback, void* context, void* data) {
  Packet* packet = static_cast<Packet*>(data);
  if (env != nullptr && js_callback != nullptr && packet != nullptr) {
    void* raw = nullptr;
    napi_value buffer = nullptr;
    if (napi_create_arraybuffer(env, packet->length, &raw, &buffer) == napi_ok && raw != nullptr) {
      memcpy(raw, packet->bytes, packet->length);
      napi_value result = nullptr;
      napi_call_function(env, nullptr, js_callback, 1, &buffer, &result);
    }
  }
  if (packet != nullptr) {
    free(packet->bytes);
    free(packet);
  }
}

/** Runs on the JS thread: reports why the loop stopped. */
void DeliverError(napi_env env, napi_value js_callback, void* context, void* data) {
  char* message = static_cast<char*>(data);
  if (env != nullptr && js_callback != nullptr && message != nullptr) {
    napi_value text = nullptr;
    if (napi_create_string_utf8(env, message, NAPI_AUTO_LENGTH, &text) == napi_ok) {
      napi_value result = nullptr;
      napi_call_function(env, nullptr, js_callback, 1, &text, &result);
    }
  }
  free(message);
}

void ReportError(const char* reason, int error_number) {
  if (g_on_error == nullptr) {
    return;
  }
  const char* detail = error_number != 0 ? strerror(error_number) : "";
  const size_t size = strlen(reason) + strlen(detail) + 32;
  char* message = static_cast<char*>(malloc(size));
  if (message == nullptr) {
    return;
  }
  snprintf(message, size, "%s (%s, errno=%d)", reason, detail, error_number);
  if (napi_call_threadsafe_function(g_on_error, message, napi_tsfn_nonblocking) != napi_ok) {
    free(message);
  }
}

void ReadLoop(int fd) {
  auto* buffer = static_cast<uint8_t*>(malloc(kPacketSize));
  if (buffer == nullptr) {
    ReportError("cannot allocate the packet buffer", 0);
    return;
  }
  while (g_reading.load()) {
    const ssize_t length = read(fd, buffer, kPacketSize);
    if (length > 0) {
      auto* packet = static_cast<Packet*>(malloc(sizeof(Packet)));
      if (packet == nullptr) {
        continue;
      }
      packet->bytes = static_cast<uint8_t*>(malloc(static_cast<size_t>(length)));
      if (packet->bytes == nullptr) {
        free(packet);
        continue;
      }
      memcpy(packet->bytes, buffer, static_cast<size_t>(length));
      packet->length = static_cast<int32_t>(length);
      if (napi_call_threadsafe_function(g_on_packet, packet, napi_tsfn_nonblocking) != napi_ok) {
        free(packet->bytes);
        free(packet);
      }
      continue;
    }
    if (length < 0 && (errno == EINTR || errno == EAGAIN)) {
      continue;
    }
    // Zero bytes or a real error: the interface is gone, and there is nothing
    // left to read from it.
    ReportError(length == 0 ? "the interface stopped delivering packets"
                            : "cannot read the interface",
                length == 0 ? 0 : errno);
    break;
  }
  free(buffer);
  g_reading.store(false);
}

napi_value StartReading(napi_env env, napi_callback_info info) {
  size_t argc = 3;
  napi_value argv[3] = {nullptr, nullptr, nullptr};
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  if (argc < 3) {
    return nullptr;
  }
  int32_t fd = -1;
  if (napi_get_value_int32(env, argv[0], &fd) != napi_ok || fd < 0) {
    return nullptr;
  }
  // A second start replaces the first: same fd, same job.
  if (g_reader.joinable()) {
    g_reading.store(false);
    g_reader.detach();
  }
  if (g_on_packet != nullptr) {
    napi_release_threadsafe_function(g_on_packet, napi_tsfn_abort);
    g_on_packet = nullptr;
  }
  if (g_on_error != nullptr) {
    napi_release_threadsafe_function(g_on_error, napi_tsfn_abort);
    g_on_error = nullptr;
  }
  napi_value name = nullptr;
  if (napi_create_string_utf8(env, "ecardbind_packet", NAPI_AUTO_LENGTH, &name) != napi_ok) {
    return nullptr;
  }
  if (napi_create_threadsafe_function(env, argv[1], nullptr, name, 0, 1, nullptr, nullptr, nullptr,
                                      DeliverPacket, &g_on_packet) != napi_ok) {
    g_on_packet = nullptr;
    return nullptr;
  }
  if (napi_create_string_utf8(env, "ecardbind_error", NAPI_AUTO_LENGTH, &name) != napi_ok) {
    return nullptr;
  }
  if (napi_create_threadsafe_function(env, argv[2], nullptr, name, 0, 1, nullptr, nullptr, nullptr,
                                      DeliverError, &g_on_error) != napi_ok) {
    g_on_error = nullptr;
    return nullptr;
  }
  g_reading.store(true);
  g_reader = std::thread(ReadLoop, static_cast<int>(fd));
  return nullptr;
}

/** Writes `length` bytes of `data` into the interface. Returns 0, or -errno. */
napi_value WritePacket(napi_env env, napi_callback_info info) {
  size_t argc = 3;
  napi_value argv[3] = {nullptr, nullptr, nullptr};
  napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
  napi_value result = nullptr;
  if (argc < 3) {
    napi_create_int32(env, -EINVAL, &result);
    return result;
  }
  int32_t fd = -1;
  void* data = nullptr;
  size_t total = 0;
  int32_t length = 0;
  if (napi_get_value_int32(env, argv[0], &fd) != napi_ok ||
      napi_get_arraybuffer_info(env, argv[1], &data, &total) != napi_ok ||
      napi_get_value_int32(env, argv[2], &length) != napi_ok || data == nullptr) {
    napi_create_int32(env, -EINVAL, &result);
    return result;
  }
  if (length < 0 || static_cast<size_t>(length) > total) {
    napi_create_int32(env, -EINVAL, &result);
    return result;
  }
  const ssize_t written = write(fd, data, static_cast<size_t>(length));
  napi_create_int32(env, written < 0 ? -errno : 0, &result);
  return result;
}

napi_value StopReading(napi_env env, napi_callback_info info) {
  g_reading.store(false);
  if (g_on_packet != nullptr) {
    napi_release_threadsafe_function(g_on_packet, napi_tsfn_abort);
    g_on_packet = nullptr;
  }
  if (g_on_error != nullptr) {
    napi_release_threadsafe_function(g_on_error, napi_tsfn_abort);
    g_on_error = nullptr;
  }
  if (g_reader.joinable()) {
    // The loop ends when its blocked read returns: either a packet arrives or
    // the interface goes away.
    g_reader.detach();
  }
  return nullptr;
}

napi_value Init(napi_env env, napi_value exports) {
  napi_property_descriptor properties[] = {
      {"startReading", nullptr, StartReading, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"writePacket", nullptr, WritePacket, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"stopReading", nullptr, StopReading, nullptr, nullptr, nullptr, napi_default, nullptr},
  };
  napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties);
  return exports;
}

}  // namespace

NAPI_MODULE(ecardbind_reader, Init)
