// NAPI shim for the aTrust tunnel inside an OpenHarmony VPN extension.
//
// The file descriptor a VPN extension creates lives in the extension's process,
// and the core engine (`libgeektrust.so`) is a c-shared library that ArkTS
// cannot call. So this shim is what the extension talks to: it dlopens the core
// engine from its own directory, keeps one handle for the process, and forwards
// the four calls the VPN shape needs.
//
// Exposes, as an ArkTS module:
//   start(sessionJson: string, policyJson: string): void
//   attachTunFd(fd: number): void
//   status(): string
//   stop(): void
//   version(): string
//
// Errors from the core engine are rethrown as JavaScript errors, message and
// all — this never invents a success.

#include <dlfcn.h>

// hilog/log.h defaults to domain 0 and a null tag, and a null tag is one of the
// two reasons a shim's lines never showed up in a device log. Both are set
// before the header, which is where OH_LOG_* takes them from.
#undef LOG_DOMAIN
#define LOG_DOMAIN 0x0000
#undef LOG_TAG
#define LOG_TAG "GeekTrustVpnEngine"
#include <hilog/log.h>
#include <mutex>
#include <string>
#include <thread>
#include <unistd.h>

#include <napi/native_api.h>

#ifndef GEEKTRUST_VPN_SOURCE_SHA256
#error "GEEKTRUST_VPN_SOURCE_SHA256 is missing — build through ohos/scripts/build-geektrust-vpn.sh."
#endif

// The shim is a committed artifact, so it has to be provable without a
// compiler: CMake digests everything in this directory into the constant below,
// and test/atrust/geektrust_vpn_artifact_test.dart recomputes it from the source
// and refuses a shim built from anything else. Exported and marked used so no
// linker or strip pass drops it.
extern "C" __attribute__((visibility("default"), used))
const char kGeekTrustVpnSourceDigest[] =
    "TECHPIE-GEEKTRUST-VPN=" GEEKTRUST_VPN_SOURCE_SHA256;

namespace {

using VersionFn = const char* (*)();
using InitFn = int (*)(const char*, const char*, char*, int);
using AttachTunFn = int (*)(int, char*, int);
using StatusFn = int (*)(char*, int);
using CloseFn = void (*)();

constexpr int kErrorBytes = 1024;
constexpr int kStatusBytes = 8192;

std::mutex g_mutex;
void* g_core = nullptr;
VersionFn g_version = nullptr;
InitFn g_init = nullptr;
AttachTunFn g_attach_tun = nullptr;
StatusFn g_status = nullptr;
CloseFn g_close = nullptr;

std::string DirOfThisLibrary() {
  Dl_info info{};
  if (dladdr(reinterpret_cast<void*>(&DirOfThisLibrary), &info) == 0 ||
      info.dli_fname == nullptr) {
    return {};
  }
  std::string path(info.dli_fname);
  const auto slash = path.find_last_of('/');
  return slash == std::string::npos ? std::string{} : path.substr(0, slash);
}

// Loads libgeektrust.so next to this shim (the app's libs directory) and binds
// its C ABI. Returns an error message, or an empty string on success.
std::string EnsureCore() {
  if (g_core != nullptr) {
    return {};
  }
  const std::string dir = DirOfThisLibrary();
  const std::string sibling = dir.empty() ? std::string{} : dir + "/libgeektrust.so";
  void* handle = sibling.empty() ? nullptr : dlopen(sibling.c_str(), RTLD_NOW | RTLD_LOCAL);
  if (handle == nullptr) {
    // Fall back to the loader's own search path.
    handle = dlopen("libgeektrust.so", RTLD_NOW | RTLD_LOCAL);
  }
  if (handle == nullptr) {
    const char* reason = dlerror();
    return std::string("libgeektrust.so could not be loaded") +
           (reason == nullptr ? "" : std::string(": ") + reason);
  }
  g_version = reinterpret_cast<VersionFn>(dlsym(handle, "geektrust_version"));
  g_init = reinterpret_cast<InitFn>(dlsym(handle, "geektrust_init"));
  g_attach_tun = reinterpret_cast<AttachTunFn>(dlsym(handle, "geektrust_attach_tun_fd"));
  g_status = reinterpret_cast<StatusFn>(dlsym(handle, "geektrust_status"));
  g_close = reinterpret_cast<CloseFn>(dlsym(handle, "geektrust_close"));
  if (g_init == nullptr || g_attach_tun == nullptr || g_status == nullptr ||
      g_close == nullptr) {
    dlclose(handle);
    g_version = nullptr;
    g_init = nullptr;
    g_attach_tun = nullptr;
    g_status = nullptr;
    g_close = nullptr;
    return std::string("libgeektrust.so does not export the geektrust_* ABI");
  }
  g_core = handle;
  return {};
}

// The engine logs through Go's slog, which writes to the process's stderr — and
// nothing on OHOS forwards a native process's stderr to hilog, so a device run
// showed a refusal with no reason attached. This hands stderr (and stdout) to a
// thread that logs each line, so the engine's own account of what it is doing
// lands in `hdc shell hilog` with everything else.
void ForwardOutputToHilog() {
  static std::once_flag once;
  std::call_once(once, []() {
    int pipeFd[2] = {-1, -1};
    if (pipe(pipeFd) != 0) {
      OH_LOG_WARN(LOG_APP, "engine output forwarding unavailable: pipe() failed");
      return;
    }
    dup2(pipeFd[1], STDOUT_FILENO);
    dup2(pipeFd[1], STDERR_FILENO);
    close(pipeFd[1]);
    OH_LOG_INFO(LOG_APP, "engine output is forwarded to this log");
    std::thread([readFd = pipeFd[0]]() {
      std::string line;
      char buffer[512];
      ssize_t count = 0;
      while ((count = read(readFd, buffer, sizeof(buffer))) > 0) {
        for (ssize_t index = 0; index < count; index++) {
          if (buffer[index] == '\n') {
            if (!line.empty()) {
              OH_LOG_INFO(LOG_APP, "engine: %{public}s", line.c_str());
              line.clear();
            }
          } else {
            line.push_back(buffer[index]);
          }
        }
        if (line.size() > 1024) {
          OH_LOG_INFO(LOG_APP, "engine: %{public}s", line.c_str());
          line.clear();
        }
      }
    }).detach();
  });
}

napi_value Throw(napi_env env, const std::string& message) {
  napi_throw_error(env, nullptr, message.c_str());
  return nullptr;
}

bool ReadString(napi_env env, napi_value value, std::string* out) {
  size_t length = 0;
  if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) {
    return false;
  }
  out->resize(length);
  size_t written = 0;
  return napi_get_value_string_utf8(env, value, out->data(), length + 1, &written) == napi_ok;
}

napi_value AttachTunFd(napi_env env, napi_callback_info info) {
  size_t argc = 1;
  napi_value args[1] = {nullptr};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  int32_t fd = -1;
  if (argc < 1 || napi_get_value_int32(env, args[0], &fd) != napi_ok) {
    return Throw(env, "attachTunFd(fd): fd must be a number");
  }
  std::lock_guard<std::mutex> guard(g_mutex);
  const std::string loadError = EnsureCore();
  if (!loadError.empty()) {
    return Throw(env, loadError);
  }
  char error[kErrorBytes] = {0};
  if (g_attach_tun(fd, error, kErrorBytes) != 0) {
    return Throw(env, error[0] == '\0' ? "the core engine refused the descriptor" : error);
  }
  napi_value undefined = nullptr;
  napi_get_undefined(env, &undefined);
  return undefined;
}

napi_value Start(napi_env env, napi_callback_info info) {
  size_t argc = 2;
  napi_value args[2] = {nullptr, nullptr};
  napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
  std::string session;
  std::string policy;
  if (argc < 2 || !ReadString(env, args[0], &session) || !ReadString(env, args[1], &policy)) {
    return Throw(env, "start(sessionJson, policyJson): both must be strings");
  }
  std::lock_guard<std::mutex> guard(g_mutex);
  const std::string loadError = EnsureCore();
  if (!loadError.empty()) {
    return Throw(env, loadError);
  }
  ForwardOutputToHilog();
  char error[kErrorBytes] = {0};
  if (g_init(session.c_str(), policy.c_str(), error, kErrorBytes) != 0) {
    return Throw(env, error[0] == '\0' ? "the core engine refused the session" : error);
  }
  napi_value undefined = nullptr;
  napi_get_undefined(env, &undefined);
  return undefined;
}

napi_value Status(napi_env env, napi_callback_info info) {
  std::lock_guard<std::mutex> guard(g_mutex);
  const std::string loadError = EnsureCore();
  if (!loadError.empty()) {
    return Throw(env, loadError);
  }
  char out[kStatusBytes] = {0};
  if (g_status(out, kStatusBytes) != 0) {
    return Throw(env, out[0] == '\0' ? "the core engine refused the status call" : out);
  }
  napi_value result = nullptr;
  napi_create_string_utf8(env, out, NAPI_AUTO_LENGTH, &result);
  return result;
}

napi_value Stop(napi_env env, napi_callback_info info) {
  std::lock_guard<std::mutex> guard(g_mutex);
  if (g_core == nullptr) {
    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
  }
  g_close();
  dlclose(g_core);
  g_core = nullptr;
  g_init = nullptr;
  g_attach_tun = nullptr;
  g_status = nullptr;
  g_close = nullptr;
  napi_value undefined = nullptr;
  napi_get_undefined(env, &undefined);
  return undefined;
}

napi_value Version(napi_env env, napi_callback_info info) {
  std::lock_guard<std::mutex> guard(g_mutex);
  const std::string loadError = EnsureCore();
  if (!loadError.empty()) {
    return Throw(env, loadError);
  }
  napi_value result = nullptr;
  napi_create_string_utf8(env, g_version == nullptr ? "" : g_version(), NAPI_AUTO_LENGTH, &result);
  return result;
}

napi_value Init(napi_env env, napi_value exports) {
  napi_property_descriptor properties[] = {
      {"start", nullptr, Start, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"attachTunFd", nullptr, AttachTunFd, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"status", nullptr, Status, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"stop", nullptr, Stop, nullptr, nullptr, nullptr, napi_default, nullptr},
      {"version", nullptr, Version, nullptr, nullptr, nullptr, napi_default, nullptr},
  };
  napi_define_properties(env, exports, sizeof(properties) / sizeof(properties[0]), properties);
  return exports;
}

napi_module g_module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "geektrust_vpn",
    .nm_priv = nullptr,
    .reserved = {0},
};

}  // namespace

extern "C" __attribute__((constructor)) void RegisterGeekTrustVpnModule() {
  napi_module_register(&g_module);
}
