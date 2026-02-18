#ifndef DLLART_BRIDGE_H
#define DLLART_BRIDGE_H

#include <stdint.h>

#ifdef _WIN32
#define DLLART_API __declspec(dllexport)
#else
#define DLLART_API __attribute__((visibility("default")))
#endif

#ifdef __cplusplus
extern "C" {
#endif

// Stable ABI version for consumers from C/C++/Rust/Python/etc.
DLLART_API int dllart_abi_version(void);

// Stable machine-readable error codes.
// Existing error_out text remains backward-compatible.
enum {
  DLLART_E_OK = 0,
  DLLART_E_INTERNAL = 1,
  DLLART_E_INVALID_ARGUMENT = 2,
  DLLART_E_NOT_INITIALIZED = 3,
  DLLART_E_RUNTIME = 4,
  DLLART_E_LIMIT_EXCEEDED = 5,
  DLLART_E_OOM = 6,
};

// Initializes embedded Dart VM/isolate for this module.
// runtime_path:
//   - optional absolute path to dartaotruntime
//   - can be NULL to use auto-lookup order:
//       1) DLLART_DART_RUNTIME
//       2) runtime near current shared library
//       3) build-time default path
// version:
//   - runtime version is checked against build-time SDK version when available
// isolate pool:
//   - number of worker isolates can be tuned via DLLART_ISOLATE_POOL_SIZE
//   - default: 1, max: 64
// error_out:
//   - optional heap-allocated UTF-8 string; free with dllart_string_free()
// return:
//   - 0 on success, non-zero on failure
DLLART_API int dllart_init(const char* runtime_path, char** error_out);

// Calls Dart top-level function:
//   String dllart_dispatch(String method, String argsJson)
// args_json/result_json use UTF-8 JSON payloads.
DLLART_API int dllart_call_json(const char* method,
                                const char* args_json,
                                char** result_json_out,
                                char** error_out);

// Batch JSON mode:
// input: JSON array of objects [{"method":"name","args":...}, ...]
// output: JSON array [{ok:true,result:...}|{ok:false,error:...}, ...]
DLLART_API int dllart_call_json_batch(const char* batch_json,
                                      char** result_json_out,
                                      char** error_out);

// Raw JSON mode (no {ok,result/error} wrapper):
//   String dllart_dispatch_raw(String method, String argsJson)
// On success returns JSON-encoded method result in result_json_out.
// On failure returns non-zero with detailed error_out.
DLLART_API int dllart_call_json_raw(const char* method,
                                    const char* args_json,
                                    char** result_json_out,
                                    char** error_out);

// Typed fast-path for methods that accept two int64 arguments and return int64.
// The Dart module should expose:
//   int dllart_dispatch_i64_2(String method, int a, int b)
DLLART_API int dllart_call_i64_2(const char* method,
                                 int64_t a,
                                 int64_t b,
                                 int64_t* result_out,
                                 char** error_out);

// Typed fast-path by method index (avoids method-name lookup on hot path).
// method_id should come from artifact metadata / generated wrappers.
DLLART_API int dllart_call_i64_2_index(int32_t method_id,
                                       int64_t a,
                                       int64_t b,
                                       int64_t* result_out,
                                       char** error_out);

// Typed fast-path for methods that accept four int64 arguments and return int64.
// The Dart module should expose:
//   int dllart_dispatch_i64_4(String method, int a, int b, int c, int d)
DLLART_API int dllart_call_i64_4(const char* method,
                                 int64_t a,
                                 int64_t b,
                                 int64_t c,
                                 int64_t d,
                                 int64_t* result_out,
                                 char** error_out);

// Typed i64_4 fast-path by method index (avoids method-name lookup).
DLLART_API int dllart_call_i64_4_index(int32_t method_id,
                                       int64_t a,
                                       int64_t b,
                                       int64_t c,
                                       int64_t d,
                                       int64_t* result_out,
                                       char** error_out);

// Typed fast-path for methods that accept two doubles and return double.
// The Dart module should expose:
//   double dllart_dispatch_f64_2(String method, double a, double b)
DLLART_API int dllart_call_f64_2(const char* method,
                                 double a,
                                 double b,
                                 double* result_out,
                                 char** error_out);

// Typed f64_2 fast-path by method index (avoids method-name lookup).
DLLART_API int dllart_call_f64_2_index(int32_t method_id,
                                       double a,
                                       double b,
                                       double* result_out,
                                       char** error_out);

// Typed fast-path for methods that accept four doubles and return double.
// The Dart module should expose:
//   double dllart_dispatch_f64_4(String method, double a, double b, double c, double d)
DLLART_API int dllart_call_f64_4(const char* method,
                                 double a,
                                 double b,
                                 double c,
                                 double d,
                                 double* result_out,
                                 char** error_out);

// Typed f64_4 fast-path by method index (avoids method-name lookup).
DLLART_API int dllart_call_f64_4_index(int32_t method_id,
                                       double a,
                                       double b,
                                       double c,
                                       double d,
                                       double* result_out,
                                       char** error_out);

// Typed fast-path for binary payloads (protobuf-ready transport).
// The Dart module should expose:
//   Uint8List dllart_dispatch_bytes(String method, Uint8List args)
DLLART_API int dllart_call_bytes(const char* method,
                                 const uint8_t* args,
                                 int32_t args_len,
                                 uint8_t** result_out,
                                 int32_t* result_len_out,
                                 char** error_out);

// Typed bytes fast-path by method index (avoids method-name lookup).
DLLART_API int dllart_call_bytes_index(int32_t method_id,
                                       const uint8_t* args,
                                       int32_t args_len,
                                       uint8_t** result_out,
                                       int32_t* result_len_out,
                                       char** error_out);

// Stops the current module isolate. Safe to call multiple times.
DLLART_API void dllart_shutdown(void);

// Frees strings returned by dllart_init/dllart_call_json.
DLLART_API void dllart_string_free(char* value);

// Frees byte buffers returned by dllart_call_bytes*.
DLLART_API void dllart_bytes_free(uint8_t* value);

// Legacy alias for compatibility with older drafts.
DLLART_API int dllart_call(const char* function_name,
                                const char* args_json,
                                char** result_json_out,
                                char** error_out);

// Last error API (thread-local):
// - code: machine-readable DLLART_E_* code
// - json: {"code":...,"message":...,"context":...}
DLLART_API int dllart_last_error_code(void);
DLLART_API int dllart_last_error_json(char** error_json_out);

#ifdef __cplusplus
}
#endif

#endif
