#include "bench_native_api.h"

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include <string>
#include <vector>

namespace {

constexpr int64_t kCpuMask = 0x7fffffff;
constexpr uint32_t kIoMask32 = 0xffffffffu;
constexpr size_t kIoBlockSize = 1u << 20;

std::vector<uint8_t> g_io_payload;

void set_error(char** error_out, const char* message) {
  if (error_out == nullptr) {
    return;
  }
  if (message == nullptr) {
    *error_out = nullptr;
    return;
  }
  const size_t len = strlen(message);
  char* out = static_cast<char*>(malloc(len + 1));
  if (out == nullptr) {
    *error_out = nullptr;
    return;
  }
  memcpy(out, message, len + 1);
  *error_out = out;
}

void fill_buffer(std::vector<uint8_t>& buffer) {
  uint32_t seed = 0xA5A5A5A5u;
  for (size_t i = 0; i < buffer.size(); i++) {
    seed ^= seed << 13;
    seed ^= seed >> 17;
    seed ^= seed << 5;
    seed &= kIoMask32;
    buffer[i] = static_cast<uint8_t>(seed & 0xffu);
  }
}

}  // namespace

extern "C" int bench_init(const char* runtime_path, char** error_out) {
  (void)runtime_path;
  if (error_out != nullptr) {
    *error_out = nullptr;
  }
  return 0;
}

extern "C" int bench_cpu_work(int64_t iterations,
                                int64_t seed,
                                int64_t* checksum_out,
                                char** error_out) {
  if (error_out != nullptr) {
    *error_out = nullptr;
  }
  if (iterations <= 0) {
    set_error(error_out, "iterations must be > 0");
    return 1;
  }
  if (checksum_out == nullptr) {
    set_error(error_out, "checksum_out is null");
    return 1;
  }

  int64_t x = seed & kCpuMask;
  int64_t acc = 0;
  for (int64_t i = 0; i < iterations; i++) {
    x = (x * 1103515245 + 12345) & kCpuMask;
    acc = (acc + ((x ^ i) & kCpuMask)) & kCpuMask;
  }

  *checksum_out = acc;
  return 0;
}

extern "C" int bench_io_write(const char* path,
                                int64_t file_mb,
                                int64_t* bytes_written_out,
                                char** error_out) {
  if (error_out != nullptr) {
    *error_out = nullptr;
  }
  if (path == nullptr || path[0] == '\0') {
    set_error(error_out, "path must be non-empty");
    return 1;
  }
  if (file_mb <= 0) {
    set_error(error_out, "file_mb must be > 0");
    return 1;
  }
  if (bytes_written_out == nullptr) {
    set_error(error_out, "bytes_written_out is null");
    return 1;
  }

  const int64_t total_bytes = file_mb * 1024 * 1024;
  std::vector<uint8_t> pattern(kIoBlockSize);
  fill_buffer(pattern);

  g_io_payload.assign(static_cast<size_t>(total_bytes), 0);
  int64_t offset = 0;
  while (offset < total_bytes) {
    const int64_t chunk =
        (total_bytes - offset) > static_cast<int64_t>(pattern.size())
            ? static_cast<int64_t>(pattern.size())
            : (total_bytes - offset);
    memcpy(g_io_payload.data() + offset, pattern.data(), static_cast<size_t>(chunk));
    offset += chunk;
  }

  *bytes_written_out = total_bytes;
  return 0;
}

extern "C" int bench_io_read(const char* path,
                               int64_t file_mb,
                               int64_t* checksum_out,
                               char** error_out) {
  if (error_out != nullptr) {
    *error_out = nullptr;
  }
  if (path == nullptr || path[0] == '\0') {
    set_error(error_out, "path must be non-empty");
    return 1;
  }
  if (file_mb <= 0) {
    set_error(error_out, "file_mb must be > 0");
    return 1;
  }
  if (checksum_out == nullptr) {
    set_error(error_out, "checksum_out is null");
    return 1;
  }

  const int64_t total_bytes = file_mb * 1024 * 1024;
  if (static_cast<int64_t>(g_io_payload.size()) != total_bytes) {
    set_error(error_out, "payload size mismatch");
    return 1;
  }

  int64_t checksum = 0;
  for (uint8_t value : g_io_payload) {
    checksum += static_cast<int64_t>(value);
  }

  g_io_payload.clear();
  g_io_payload.shrink_to_fit();

  *checksum_out = checksum;
  return 0;
}

extern "C" void bench_shutdown(void) {}

extern "C" void bench_string_free(char* value) {
  free(value);
}
