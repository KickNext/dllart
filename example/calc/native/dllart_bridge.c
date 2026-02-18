#if defined(__linux__) && !defined(_GNU_SOURCE)
#define _GNU_SOURCE
#endif

#include "dllart_bridge.h"

#include <ctype.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if defined(_WIN32)
#include <windows.h>
#else
#include <dlfcn.h>
#include <pthread.h>
#include <sys/stat.h>
#endif

#include "dart_api.h"

#ifndef DLLART_DEFAULT_RUNTIME_PATH
#define DLLART_DEFAULT_RUNTIME_PATH ""
#endif

#ifndef DLLART_EXPECTED_DART_VERSION
#define DLLART_EXPECTED_DART_VERSION ""
#endif

#ifndef DLLART_JSON_IN_MAX_BYTES
#define DLLART_JSON_IN_MAX_BYTES (1024 * 1024)
#endif

#ifndef DLLART_JSON_OUT_MAX_BYTES
#define DLLART_JSON_OUT_MAX_BYTES (8 * 1024 * 1024)
#endif

#ifndef DLLART_BYTES_IN_MAX_BYTES
#define DLLART_BYTES_IN_MAX_BYTES (4 * 1024 * 1024)
#endif

#ifndef DLLART_BYTES_OUT_MAX_BYTES
#define DLLART_BYTES_OUT_MAX_BYTES (16 * 1024 * 1024)
#endif

#ifndef DLLART_METHOD_CACHE_MAX_ENTRIES
#define DLLART_METHOD_CACHE_MAX_ENTRIES 2048
#endif

#ifndef DLLART_RUNTIME_PROFILE
#define DLLART_RUNTIME_PROFILE "full"
#endif

#if defined(_WIN32)
#define DLLART_RUNTIME_BASENAME "dartaotruntime.exe"
#define DLLART_PATH_SEP '\\'
#else
#define DLLART_RUNTIME_BASENAME "dartaotruntime"
#define DLLART_PATH_SEP '/'
#endif

extern const uint8_t kDartVmSnapshotData[];
extern const uint8_t kDartVmSnapshotInstructions[];
extern const uint8_t kDartIsolateSnapshotData[];
extern const uint8_t kDartIsolateSnapshotInstructions[];

typedef char* (*Dart_SetVMFlagsFn)(int argc, const char** argv);
typedef char* (*Dart_InitializeFn)(Dart_InitializeParams* params);
typedef char* (*Dart_CleanupFn)(void);
typedef void (*Dart_IsolateFlagsInitializeFn)(Dart_IsolateFlags* flags);
typedef Dart_Isolate (*Dart_CreateIsolateGroupFn)(const char* script_uri,
                                                   const char* name,
                                                   const uint8_t* snapshot_data,
                                                   const uint8_t* snapshot_instructions,
                                                   Dart_IsolateFlags* flags,
                                                   void* isolate_group_data,
                                                   void* isolate_data,
                                                   char** error);
typedef void (*Dart_EnterIsolateFn)(Dart_Isolate isolate);
typedef void (*Dart_ExitIsolateFn)(void);
typedef void (*Dart_ShutdownIsolateFn)(void);
typedef void (*Dart_EnterScopeFn)(void);
typedef void (*Dart_ExitScopeFn)(void);
typedef bool (*Dart_IsErrorFn)(Dart_Handle handle);
typedef const char* (*Dart_GetErrorFn)(Dart_Handle handle);
typedef Dart_Handle (*Dart_RootLibraryFn)(void);
typedef Dart_Handle (*Dart_NewStringFromCStringFn)(const char* value);
typedef Dart_Handle (*Dart_HandleFromPersistentFn)(Dart_PersistentHandle object);
typedef Dart_PersistentHandle (*Dart_NewPersistentHandleFn)(Dart_Handle object);
typedef void (*Dart_DeletePersistentHandleFn)(Dart_PersistentHandle object);
typedef Dart_Handle (*Dart_NewIntegerFn)(int64_t value);
typedef Dart_Handle (*Dart_NewDoubleFn)(double value);
typedef const char* (*Dart_VersionStringFn)(void);
typedef Dart_Handle (*Dart_InvokeFn)(Dart_Handle target,
                                     Dart_Handle name,
                                     intptr_t number_of_arguments,
                                     Dart_Handle* arguments);
typedef Dart_Handle (*Dart_StringToCStringFn)(Dart_Handle str, const char** cstr);
typedef Dart_Handle (*Dart_IntegerToInt64Fn)(Dart_Handle integer,
                                             int64_t* value);
typedef Dart_Handle (*Dart_DoubleValueFn)(Dart_Handle double_obj,
                                          double* value);
typedef Dart_Handle (*Dart_NewTypedDataFn)(Dart_TypedData_Type type,
                                           intptr_t length);
typedef Dart_Handle (*Dart_ListLengthFn)(Dart_Handle list, intptr_t* length);
typedef Dart_Handle (*Dart_ListGetAsBytesFn)(Dart_Handle list,
                                             intptr_t offset,
                                             uint8_t* native_array,
                                             intptr_t length);
typedef Dart_Handle (*Dart_ListSetAsBytesFn)(Dart_Handle list,
                                             intptr_t offset,
                                             const uint8_t* native_array,
                                             intptr_t length);

typedef struct {
  Dart_SetVMFlagsFn Dart_SetVMFlags;
  Dart_InitializeFn Dart_Initialize;
  Dart_CleanupFn Dart_Cleanup;
  Dart_IsolateFlagsInitializeFn Dart_IsolateFlagsInitialize;
  Dart_CreateIsolateGroupFn Dart_CreateIsolateGroup;
  Dart_EnterIsolateFn Dart_EnterIsolate;
  Dart_ExitIsolateFn Dart_ExitIsolate;
  Dart_ShutdownIsolateFn Dart_ShutdownIsolate;
  Dart_EnterScopeFn Dart_EnterScope;
  Dart_ExitScopeFn Dart_ExitScope;
  Dart_IsErrorFn Dart_IsError;
  Dart_GetErrorFn Dart_GetError;
  Dart_RootLibraryFn Dart_RootLibrary;
  Dart_NewStringFromCStringFn Dart_NewStringFromCString;
  Dart_HandleFromPersistentFn Dart_HandleFromPersistent;
  Dart_NewPersistentHandleFn Dart_NewPersistentHandle;
  Dart_DeletePersistentHandleFn Dart_DeletePersistentHandle;
  Dart_NewIntegerFn Dart_NewInteger;
  Dart_NewDoubleFn Dart_NewDouble;
  Dart_VersionStringFn Dart_VersionString;
  Dart_InvokeFn Dart_Invoke;
  Dart_StringToCStringFn Dart_StringToCString;
  Dart_IntegerToInt64Fn Dart_IntegerToInt64;
  Dart_DoubleValueFn Dart_DoubleValue;
  Dart_NewTypedDataFn Dart_NewTypedData;
  Dart_ListLengthFn Dart_ListLength;
  Dart_ListGetAsBytesFn Dart_ListGetAsBytes;
  Dart_ListSetAsBytesFn Dart_ListSetAsBytes;
} DartApi;

#if defined(_WIN32)
typedef HMODULE dllart_library_t;
#else
typedef void* dllart_library_t;
#endif

typedef struct {
  char* method_name;
  Dart_PersistentHandle handle;
} DllartMethodHandle;

typedef struct {
  Dart_Isolate isolate;
  Dart_PersistentHandle root_library_handle;
  Dart_PersistentHandle dispatch_json_handle;
  Dart_PersistentHandle dispatch_json_batch_handle;
  Dart_PersistentHandle dispatch_json_raw_handle;
  Dart_PersistentHandle dispatch_i64_2_handle;
  Dart_PersistentHandle dispatch_i64_2_index_handle;
  Dart_PersistentHandle dispatch_i64_4_handle;
  Dart_PersistentHandle dispatch_i64_4_index_handle;
  Dart_PersistentHandle dispatch_f64_2_handle;
  Dart_PersistentHandle dispatch_f64_2_index_handle;
  Dart_PersistentHandle dispatch_f64_4_handle;
  Dart_PersistentHandle dispatch_f64_4_index_handle;
  Dart_PersistentHandle dispatch_bytes_handle;
  Dart_PersistentHandle dispatch_bytes_index_handle;
  DllartMethodHandle* method_handles;
  size_t method_handles_count;
  size_t method_handles_capacity;
#if defined(_WIN32)
  CRITICAL_SECTION call_mutex;
#else
  pthread_mutex_t call_mutex;
#endif
  bool call_mutex_ready;
} DllartIsolateState;

typedef struct {
  dllart_library_t runtime_handle;
  char* runtime_path;
  bool vm_initialized;
  DllartIsolateState* isolates;
  size_t isolate_count;
  size_t next_isolate_index;
  DartApi api;
} DllartState;

static DllartState g_state = {0};

#if defined(_MSC_VER)
__declspec(thread) static int g_dllart_last_error_code = DLLART_E_OK;
__declspec(thread) static char* g_dllart_last_error_json = NULL;
#else
static _Thread_local int g_dllart_last_error_code = DLLART_E_OK;
static _Thread_local char* g_dllart_last_error_json = NULL;
#endif

static int dllart_set_error(char** error_out, const char* message);
static int dllart_set_error_code(char** error_out,
                                 int code,
                                 const char* message);
static int dllart_set_invalid_argument(char** error_out, const char* message);
static int dllart_set_not_initialized(char** error_out, const char* message);
static int dllart_set_limit_exceeded(char** error_out, const char* message);
static int dllart_set_error_call_context(char** error_out,
                                         const char* context,
                                         const char* detail,
                                         const char* abi_name,
                                         const char* method_name,
                                         int32_t method_id,
                                         const char* input_type);
static void dllart_clear_last_error(void);
static void dllart_record_last_error(int code,
                                     const char* message,
                                     const char* context);
static int dllart_check_handle_call(Dart_Handle handle,
                                    const char* context,
                                    const char* abi_name,
                                    const char* method_name,
                                    int32_t method_id,
                                    const char* input_type,
                                    char** error_out);
static int dllart_validate_cstring_length(const char* value,
                                          size_t max_bytes,
                                          const char* field_name,
                                          char** error_out);

#if defined(_WIN32)
static INIT_ONCE g_mutex_once = INIT_ONCE_STATIC_INIT;
static CRITICAL_SECTION g_state_mutex;

static BOOL CALLBACK dllart_init_mutex_once(PINIT_ONCE init_once,
                                            PVOID parameter,
                                            PVOID* context) {
  (void)init_once;
  (void)parameter;
  (void)context;
  InitializeCriticalSection(&g_state_mutex);
  return TRUE;
}

static void dllart_mutex_lock(void) {
  InitOnceExecuteOnce(&g_mutex_once, dllart_init_mutex_once, NULL, NULL);
  EnterCriticalSection(&g_state_mutex);
}

static void dllart_mutex_unlock(void) {
  LeaveCriticalSection(&g_state_mutex);
}
#else
static pthread_mutex_t g_state_mutex = PTHREAD_MUTEX_INITIALIZER;

static void dllart_mutex_lock(void) {
  pthread_mutex_lock(&g_state_mutex);
}

static void dllart_mutex_unlock(void) {
  pthread_mutex_unlock(&g_state_mutex);
}
#endif

#if defined(_WIN32)
static int dllart_call_mutex_init(DllartIsolateState* state, char** error_out) {
  (void)error_out;
  InitializeCriticalSection(&state->call_mutex);
  state->call_mutex_ready = true;
  return 0;
}

static void dllart_call_mutex_lock(DllartIsolateState* state) {
  EnterCriticalSection(&state->call_mutex);
}

static void dllart_call_mutex_unlock(DllartIsolateState* state) {
  LeaveCriticalSection(&state->call_mutex);
}

static void dllart_call_mutex_destroy(DllartIsolateState* state) {
  if (state->call_mutex_ready) {
    DeleteCriticalSection(&state->call_mutex);
    state->call_mutex_ready = false;
  }
}
#else
static int dllart_call_mutex_init(DllartIsolateState* state, char** error_out) {
  if (pthread_mutex_init(&state->call_mutex, NULL) != 0) {
    return dllart_set_error(error_out, "Failed to initialize isolate mutex");
  }
  state->call_mutex_ready = true;
  return 0;
}

static void dllart_call_mutex_lock(DllartIsolateState* state) {
  pthread_mutex_lock(&state->call_mutex);
}

static void dllart_call_mutex_unlock(DllartIsolateState* state) {
  pthread_mutex_unlock(&state->call_mutex);
}

static void dllart_call_mutex_destroy(DllartIsolateState* state) {
  if (state->call_mutex_ready) {
    pthread_mutex_destroy(&state->call_mutex);
    state->call_mutex_ready = false;
  }
}
#endif

static char* dllart_strdup(const char* text) {
  if (text == NULL) {
    return NULL;
  }
  const size_t len = strlen(text);
  char* out = (char*)malloc(len + 1);
  if (out == NULL) {
    return NULL;
  }
  memcpy(out, text, len + 1);
  return out;
}

static bool dllart_file_exists(const char* path) {
  if (path == NULL || path[0] == '\0') {
    return false;
  }
#if defined(_WIN32)
  DWORD attrs = GetFileAttributesA(path);
  if (attrs == INVALID_FILE_ATTRIBUTES) {
    return false;
  }
  return (attrs & FILE_ATTRIBUTE_DIRECTORY) == 0;
#else
  struct stat st;
  if (stat(path, &st) != 0) {
    return false;
  }
  return S_ISREG(st.st_mode);
#endif
}

static char* dllart_dirname_dup(const char* path) {
  if (path == NULL || path[0] == '\0') {
    return NULL;
  }

  size_t len = strlen(path);
  while (len > 0 && (path[len - 1] == '/' || path[len - 1] == '\\')) {
    len--;
  }
  if (len == 0) {
    return dllart_strdup(".");
  }

  size_t cut = len;
  while (cut > 0 && path[cut - 1] != '/' && path[cut - 1] != '\\') {
    cut--;
  }
  if (cut == 0) {
    return dllart_strdup(".");
  }
  while (cut > 1 && (path[cut - 1] == '/' || path[cut - 1] == '\\')) {
    cut--;
  }

  char* out = (char*)malloc(cut + 1);
  if (out == NULL) {
    return NULL;
  }
  memcpy(out, path, cut);
  out[cut] = '\0';
  return out;
}

static char* dllart_join_path(const char* left, const char* right) {
  if (left == NULL || right == NULL) {
    return NULL;
  }

  const size_t left_len = strlen(left);
  const size_t right_len = strlen(right);
  const bool need_sep = left_len > 0 && left[left_len - 1] != '/' &&
                        left[left_len - 1] != '\\';
  const size_t total = left_len + (need_sep ? 1 : 0) + right_len + 1;
  char* out = (char*)malloc(total);
  if (out == NULL) {
    return NULL;
  }

  size_t pos = 0;
  memcpy(out + pos, left, left_len);
  pos += left_len;
  if (need_sep) {
    out[pos++] = DLLART_PATH_SEP;
  }
  memcpy(out + pos, right, right_len);
  pos += right_len;
  out[pos] = '\0';
  return out;
}

static char* dllart_self_library_path(void) {
#if defined(_WIN32)
  HMODULE module = NULL;
  if (!GetModuleHandleExA(
          GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS |
              GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
          (LPCSTR)&dllart_self_library_path, &module)) {
    return NULL;
  }

  DWORD size = MAX_PATH;
  for (;;) {
    char* buffer = (char*)malloc((size_t)size + 1);
    if (buffer == NULL) {
      return NULL;
    }
    DWORD written = GetModuleFileNameA(module, buffer, size);
    if (written == 0) {
      free(buffer);
      return NULL;
    }
    if (written < size - 1) {
      buffer[written] = '\0';
      return buffer;
    }
    free(buffer);
    if (size >= 32768) {
      return NULL;
    }
    size *= 2;
  }
#else
  Dl_info info;
  if (dladdr((void*)&dllart_self_library_path, &info) == 0 ||
      info.dli_fname == NULL) {
    return NULL;
  }
  return dllart_strdup(info.dli_fname);
#endif
}

static char* dllart_find_runtime_near_self(void) {
  char* self_path = dllart_self_library_path();
  if (self_path == NULL) {
    return NULL;
  }

  char* self_dir = dllart_dirname_dup(self_path);
  free(self_path);
  if (self_dir == NULL) {
    return NULL;
  }

  // 1) <library_dir>/dartaotruntime
  char* candidate = dllart_join_path(self_dir, DLLART_RUNTIME_BASENAME);
  if (candidate != NULL && dllart_file_exists(candidate)) {
    free(self_dir);
    return candidate;
  }
  free(candidate);

  // 2) <library_dir>/runtime/dartaotruntime
  char* runtime_dir = dllart_join_path(self_dir, "runtime");
  if (runtime_dir != NULL) {
    candidate = dllart_join_path(runtime_dir, DLLART_RUNTIME_BASENAME);
    free(runtime_dir);
    if (candidate != NULL && dllart_file_exists(candidate)) {
      free(self_dir);
      return candidate;
    }
    free(candidate);
  }

  // 3) <library_dir>/../runtime/dartaotruntime
  char* parent_dir = dllart_dirname_dup(self_dir);
  if (parent_dir != NULL) {
    char* parent_runtime_dir = dllart_join_path(parent_dir, "runtime");
    free(parent_dir);
    if (parent_runtime_dir != NULL) {
      candidate = dllart_join_path(parent_runtime_dir, DLLART_RUNTIME_BASENAME);
      free(parent_runtime_dir);
      if (candidate != NULL && dllart_file_exists(candidate)) {
        free(self_dir);
        return candidate;
      }
      free(candidate);
    }
  }

  free(self_dir);
  return NULL;
}

static const char* dllart_pick_runtime_path(const char* runtime_path,
                                            char** owned_path_out) {
  if (owned_path_out != NULL) {
    *owned_path_out = NULL;
  }

  if (runtime_path != NULL && runtime_path[0] != '\0') {
    return runtime_path;
  }

  {
    const char* from_env = getenv("DLLART_DART_RUNTIME");
    if (from_env != NULL && from_env[0] != '\0') {
      return from_env;
    }
  }

  if (owned_path_out != NULL) {
    char* from_bundle = dllart_find_runtime_near_self();
    if (from_bundle != NULL) {
      *owned_path_out = from_bundle;
      return from_bundle;
    }
  }

  if (DLLART_DEFAULT_RUNTIME_PATH[0] != '\0') {
    return DLLART_DEFAULT_RUNTIME_PATH;
  }
  return NULL;
}

static bool dllart_version_prefix_matches(const char* actual,
                                          const char* expected) {
  if (actual == NULL || expected == NULL) {
    return false;
  }
  const size_t expected_len = strlen(expected);
  if (expected_len == 0) {
    return true;
  }
  if (strncmp(actual, expected, expected_len) != 0) {
    return false;
  }
  const char next = actual[expected_len];
  return next == '\0' || next == ' ' || next == '-' || next == '+' ||
         next == '(';
}

static int dllart_validate_runtime_version(char** error_out) {
  if (DLLART_EXPECTED_DART_VERSION[0] == '\0') {
    return 0;
  }
  if (g_state.api.Dart_VersionString == NULL) {
    return dllart_set_error(
        error_out, "Cannot validate runtime version: Dart_VersionString missing");
  }

  const char* actual = g_state.api.Dart_VersionString();
  if (actual == NULL || actual[0] == '\0') {
    return dllart_set_error(
        error_out, "Cannot validate runtime version: empty Dart_VersionString");
  }

  if (dllart_version_prefix_matches(actual, DLLART_EXPECTED_DART_VERSION)) {
    return 0;
  }

  const char* runtime_path =
      g_state.runtime_path != NULL ? g_state.runtime_path : "(unknown)";
  const size_t size = strlen(DLLART_EXPECTED_DART_VERSION) + strlen(actual) +
                      strlen(runtime_path) + 128;
  char* message = (char*)malloc(size);
  if (message == NULL) {
    return dllart_set_error(error_out, "Out of memory while reporting version mismatch");
  }
  snprintf(message, size,
           "Dart runtime version mismatch (expected %s, got %s) at %s",
           DLLART_EXPECTED_DART_VERSION, actual, runtime_path);
  if (error_out != NULL) {
    *error_out = message;
  } else {
    free(message);
  }
  return -1;
}

static const char* dllart_error_code_name(int code) {
  switch (code) {
    case DLLART_E_OK:
      return "DLLART_E_OK";
    case DLLART_E_INTERNAL:
      return "DLLART_E_INTERNAL";
    case DLLART_E_INVALID_ARGUMENT:
      return "DLLART_E_INVALID_ARGUMENT";
    case DLLART_E_NOT_INITIALIZED:
      return "DLLART_E_NOT_INITIALIZED";
    case DLLART_E_RUNTIME:
      return "DLLART_E_RUNTIME";
    case DLLART_E_LIMIT_EXCEEDED:
      return "DLLART_E_LIMIT_EXCEEDED";
    case DLLART_E_OOM:
      return "DLLART_E_OOM";
    default:
      return "DLLART_E_UNKNOWN";
  }
}

static char* dllart_json_escape(const char* input) {
  const char* text = input != NULL ? input : "";
  size_t extra = 0;
  for (const char* p = text; *p != '\0'; p++) {
    if (*p == '"' || *p == '\\' || *p == '\n' || *p == '\r' || *p == '\t') {
      extra++;
    }
  }
  const size_t len = strlen(text);
  char* out = (char*)malloc(len + extra + 1);
  if (out == NULL) {
    return NULL;
  }
  size_t pos = 0;
  for (const char* p = text; *p != '\0'; p++) {
    switch (*p) {
      case '"':
        out[pos++] = '\\';
        out[pos++] = '"';
        break;
      case '\\':
        out[pos++] = '\\';
        out[pos++] = '\\';
        break;
      case '\n':
        out[pos++] = '\\';
        out[pos++] = 'n';
        break;
      case '\r':
        out[pos++] = '\\';
        out[pos++] = 'r';
        break;
      case '\t':
        out[pos++] = '\\';
        out[pos++] = 't';
        break;
      default:
        out[pos++] = *p;
        break;
    }
  }
  out[pos] = '\0';
  return out;
}

static void dllart_clear_last_error(void) {
  g_dllart_last_error_code = DLLART_E_OK;
  free(g_dllart_last_error_json);
  g_dllart_last_error_json = NULL;
}

static void dllart_record_last_error(int code,
                                     const char* message,
                                     const char* context) {
  g_dllart_last_error_code = code;
  free(g_dllart_last_error_json);
  g_dllart_last_error_json = NULL;

  char* escaped_message = dllart_json_escape(message != NULL ? message : "");
  char* escaped_context = dllart_json_escape(context != NULL ? context : "");
  if (escaped_message == NULL || escaped_context == NULL) {
    free(escaped_message);
    free(escaped_context);
    return;
  }

  const char* code_name = dllart_error_code_name(code);
  const size_t size = strlen(code_name) + strlen(escaped_message) +
                      strlen(escaped_context) + 128;
  char* json = (char*)malloc(size);
  if (json != NULL) {
    snprintf(json, size,
             "{\"code\":%d,\"code_name\":\"%s\",\"message\":\"%s\",\"context\":\"%s\"}",
             code, code_name, escaped_message, escaped_context);
    g_dllart_last_error_json = json;
  }

  free(escaped_message);
  free(escaped_context);
}

static int dllart_set_error_code(char** error_out,
                                 int code,
                                 const char* message) {
  const char* safe = message != NULL ? message : "Unknown error";
  dllart_record_last_error(code, safe, NULL);
  if (error_out != NULL) {
    *error_out = dllart_strdup(safe);
  }
  return -1;
}

static int dllart_set_error(char** error_out, const char* message) {
  return dllart_set_error_code(error_out, DLLART_E_INTERNAL, message);
}

static int dllart_set_invalid_argument(char** error_out, const char* message) {
  return dllart_set_error_code(error_out, DLLART_E_INVALID_ARGUMENT, message);
}

static int dllart_set_not_initialized(char** error_out, const char* message) {
  return dllart_set_error_code(error_out, DLLART_E_NOT_INITIALIZED, message);
}

static int dllart_set_limit_exceeded(char** error_out, const char* message) {
  return dllart_set_error_code(error_out, DLLART_E_LIMIT_EXCEEDED, message);
}

static int dllart_set_error_with_context(char** error_out,
                                         const char* context,
                                         const char* detail) {
  const char* safe_context = context != NULL ? context : "dllart";
  const char* safe_detail = detail != NULL ? detail : "unknown";
  const size_t size = strlen(safe_context) + strlen(safe_detail) + 3;
  char* message = (char*)malloc(size);
  if (message == NULL) {
    return dllart_set_error_code(
        error_out, DLLART_E_OOM, "Out of memory while building error");
  }
  snprintf(message, size, "%s: %s", safe_context, safe_detail);
  dllart_record_last_error(DLLART_E_RUNTIME, message, safe_context);
  if (error_out != NULL) {
    *error_out = message;
  } else {
    free(message);
  }
  return -1;
}

static int dllart_set_error_call_context(char** error_out,
                                         const char* context,
                                         const char* detail,
                                         const char* abi_name,
                                         const char* method_name,
                                         int32_t method_id,
                                         const char* input_type) {
  const char* safe_context = context != NULL ? context : "dllart";
  const char* safe_detail = detail != NULL ? detail : "unknown";
  const char* safe_abi = abi_name != NULL ? abi_name : "unknown";
  const char* safe_input = input_type != NULL ? input_type : "unknown";
  const char* safe_method = method_name;
  char method_buf[64];
  if (safe_method == NULL || safe_method[0] == '\0') {
    snprintf(method_buf, sizeof(method_buf), "id=%d", (int)method_id);
    safe_method = method_buf;
  }

  const size_t size = strlen(safe_context) + strlen(safe_detail) +
                      strlen(safe_abi) + strlen(safe_method) +
                      strlen(safe_input) + 64;
  char* message = (char*)malloc(size);
  if (message == NULL) {
    return dllart_set_error_code(
        error_out, DLLART_E_OOM, "Out of memory while building error");
  }

  snprintf(message, size, "%s [abi=%s, method=%s, input=%s]: %s", safe_context,
           safe_abi, safe_method, safe_input, safe_detail);
  dllart_record_last_error(DLLART_E_RUNTIME, message, safe_context);
  if (error_out != NULL) {
    *error_out = message;
  } else {
    free(message);
  }
  return -1;
}

static int dllart_check_handle_call(Dart_Handle handle,
                                    const char* context,
                                    const char* abi_name,
                                    const char* method_name,
                                    int32_t method_id,
                                    const char* input_type,
                                    char** error_out) {
  if (!g_state.api.Dart_IsError(handle)) {
    return 0;
  }
  {
    const char* detail = g_state.api.Dart_GetError(handle);
    return dllart_set_error_call_context(error_out, context, detail, abi_name,
                                         method_name, method_id, input_type);
  }
}

static int dllart_validate_cstring_length(const char* value,
                                          size_t max_bytes,
                                          const char* field_name,
                                          char** error_out) {
  const char* safe_field = field_name != NULL ? field_name : "value";
  if (value == NULL) {
    const size_t size = strlen(safe_field) + 32;
    char* message = (char*)malloc(size);
    if (message == NULL) {
      return dllart_set_error_code(
          error_out, DLLART_E_OOM, "Out of memory while validating input");
    }
    snprintf(message, size, "%s cannot be null", safe_field);
    const int rc = dllart_set_invalid_argument(error_out, message);
    free(message);
    return rc;
  }

  const size_t len = strlen(value);
  if (len <= max_bytes) {
    return 0;
  }

  const size_t size = strlen(safe_field) + 128;
  char* message = (char*)malloc(size);
  if (message == NULL) {
    return dllart_set_error_code(
        error_out, DLLART_E_OOM, "Out of memory while validating input");
  }
  snprintf(message, size,
           "%s exceeds max size (%zu > %zu bytes)",
           safe_field,
           len,
           max_bytes);
  const int rc = dllart_set_limit_exceeded(error_out, message);
  free(message);
  return rc;
}

static bool dllart_case_contains(const char* text, const char* needle) {
  if (text == NULL || needle == NULL || needle[0] == '\0') {
    return false;
  }

  const size_t needle_len = strlen(needle);
  for (const char* p = text; *p != '\0'; p++) {
    size_t i = 0;
    while (i < needle_len && p[i] != '\0') {
      const int a = tolower((unsigned char)p[i]);
      const int b = tolower((unsigned char)needle[i]);
      if (a != b) {
        break;
      }
      i++;
    }
    if (i == needle_len) {
      return true;
    }
  }
  return false;
}

static bool dllart_is_already_initialized_error(const char* message) {
  return dllart_case_contains(message, "already") &&
         (dllart_case_contains(message, "init") ||
          dllart_case_contains(message, "flag") ||
          dllart_case_contains(message, "set"));
}

#if defined(_WIN32)
static char* dllart_win32_error_string(DWORD code) {
  LPSTR message_buffer = NULL;
  const DWORD size = FormatMessageA(
      FORMAT_MESSAGE_ALLOCATE_BUFFER | FORMAT_MESSAGE_FROM_SYSTEM |
          FORMAT_MESSAGE_IGNORE_INSERTS,
      NULL,
      code,
      MAKELANGID(LANG_NEUTRAL, SUBLANG_DEFAULT),
      (LPSTR)&message_buffer,
      0,
      NULL);

  if (size == 0 || message_buffer == NULL) {
    return dllart_strdup("Unknown Win32 error");
  }

  char* out = dllart_strdup(message_buffer);
  LocalFree(message_buffer);
  return out;
}

static int dllart_dlopen_path(const char* path,
                              dllart_library_t* out,
                              char** error_out) {
  HMODULE handle = LoadLibraryA(path);
  if (handle == NULL) {
    char* detail = dllart_win32_error_string(GetLastError());
    const int rc = dllart_set_error_with_context(
        error_out, "LoadLibraryA(dartaotruntime) failed", detail);
    free(detail);
    return rc;
  }
  *out = handle;
  return 0;
}

static void* dllart_dlsym(dllart_library_t handle, const char* symbol) {
  FARPROC proc = GetProcAddress(handle, symbol);
  return (void*)proc;
}

static void dllart_dlclose(dllart_library_t handle) {
  if (handle != NULL) {
    FreeLibrary(handle);
  }
}
#else
static int dllart_dlopen_path(const char* path,
                              dllart_library_t* out,
                              char** error_out) {
  void* handle = dlopen(path, RTLD_NOW | RTLD_GLOBAL);
  if (handle == NULL) {
    return dllart_set_error_with_context(
        error_out, "dlopen(dartaotruntime) failed", dlerror());
  }
  *out = handle;
  return 0;
}

static void* dllart_dlsym(dllart_library_t handle, const char* symbol) {
  return dlsym(handle, symbol);
}

static void dllart_dlclose(dllart_library_t handle) {
  if (handle != NULL) {
    dlclose(handle);
  }
}
#endif

#define DLLART_LOAD(api_field)                                                  \
  do {                                                                          \
    g_state.api.api_field =                                                     \
        (api_field##Fn)dllart_dlsym(g_state.runtime_handle, #api_field);       \
    if (g_state.api.api_field == NULL) {                                        \
      return dllart_set_error(                                                  \
          error_out,                                                             \
          "Cannot resolve Dart runtime symbol: " #api_field);                  \
    }                                                                           \
  } while (0)

static int dllart_load_runtime_symbols(char** error_out) {
  DLLART_LOAD(Dart_SetVMFlags);
  DLLART_LOAD(Dart_Initialize);
  DLLART_LOAD(Dart_Cleanup);
  DLLART_LOAD(Dart_IsolateFlagsInitialize);
  DLLART_LOAD(Dart_CreateIsolateGroup);
  DLLART_LOAD(Dart_EnterIsolate);
  DLLART_LOAD(Dart_ExitIsolate);
  DLLART_LOAD(Dart_ShutdownIsolate);
  DLLART_LOAD(Dart_EnterScope);
  DLLART_LOAD(Dart_ExitScope);
  DLLART_LOAD(Dart_IsError);
  DLLART_LOAD(Dart_GetError);
  DLLART_LOAD(Dart_RootLibrary);
  DLLART_LOAD(Dart_NewStringFromCString);
  DLLART_LOAD(Dart_HandleFromPersistent);
  DLLART_LOAD(Dart_NewPersistentHandle);
  DLLART_LOAD(Dart_DeletePersistentHandle);
  DLLART_LOAD(Dart_NewInteger);
  DLLART_LOAD(Dart_NewDouble);
  DLLART_LOAD(Dart_VersionString);
  DLLART_LOAD(Dart_Invoke);
  DLLART_LOAD(Dart_StringToCString);
  DLLART_LOAD(Dart_IntegerToInt64);
  DLLART_LOAD(Dart_DoubleValue);
  DLLART_LOAD(Dart_NewTypedData);
  DLLART_LOAD(Dart_ListLength);
  DLLART_LOAD(Dart_ListGetAsBytes);
  DLLART_LOAD(Dart_ListSetAsBytes);
  return 0;
}

static int dllart_open_runtime(const char* runtime_path, char** error_out) {
  if (g_state.runtime_handle != NULL) {
    return 0;
  }

  {
    char* owned_path = NULL;
    const char* picked_path = dllart_pick_runtime_path(runtime_path, &owned_path);
    if (picked_path == NULL) {
      free(owned_path);
      return dllart_set_error(
          error_out,
          "No Dart runtime path provided. Pass runtime_path, set "
          "DLLART_DART_RUNTIME, bundle runtime near library, or build with "
          "DLLART_DEFAULT_RUNTIME_PATH.");
    }

    if (dllart_dlopen_path(picked_path, &g_state.runtime_handle, error_out) != 0) {
      // If auto bundle path is broken, try build-time fallback before failing.
      if (owned_path != NULL && DLLART_DEFAULT_RUNTIME_PATH[0] != '\0' &&
          strcmp(picked_path, DLLART_DEFAULT_RUNTIME_PATH) != 0) {
        if (error_out != NULL && *error_out != NULL) {
          free(*error_out);
          *error_out = NULL;
        }
        free(owned_path);
        owned_path = NULL;
        picked_path = DLLART_DEFAULT_RUNTIME_PATH;
        if (dllart_dlopen_path(
                picked_path, &g_state.runtime_handle, error_out) != 0) {
          return -1;
        }
      } else {
        free(owned_path);
        return -1;
      }
    }
    if (owned_path != NULL) {
      g_state.runtime_path = owned_path;
    } else {
      g_state.runtime_path = dllart_strdup(picked_path);
    }
  }

  {
    const int load_status = dllart_load_runtime_symbols(error_out);
    if (load_status != 0) {
      dllart_dlclose(g_state.runtime_handle);
      g_state.runtime_handle = NULL;
      free(g_state.runtime_path);
      g_state.runtime_path = NULL;
      memset(&g_state.api, 0, sizeof(g_state.api));
      return load_status;
    }
  }

  {
    const int version_status = dllart_validate_runtime_version(error_out);
    if (version_status != 0) {
      dllart_dlclose(g_state.runtime_handle);
      g_state.runtime_handle = NULL;
      free(g_state.runtime_path);
      g_state.runtime_path = NULL;
      memset(&g_state.api, 0, sizeof(g_state.api));
      return version_status;
    }
  }

  return 0;
}

static int dllart_initialize_vm(char** error_out) {
  if (g_state.vm_initialized) {
    return 0;
  }

  {
    const char* vm_args[] = {
        "--precompilation",
    };

    char* flags_error = g_state.api.Dart_SetVMFlags(1, vm_args);
    if (flags_error != NULL) {
      if (!dllart_is_already_initialized_error(flags_error)) {
        const int rc = dllart_set_error_with_context(
            error_out, "Dart_SetVMFlags failed", flags_error);
        free(flags_error);
        return rc;
      }
      free(flags_error);
    }
  }

  {
    Dart_InitializeParams params;
    memset(&params, 0, sizeof(params));
    params.version = DART_INITIALIZE_PARAMS_CURRENT_VERSION;
    params.vm_snapshot_data = kDartVmSnapshotData;
    params.vm_snapshot_instructions = kDartVmSnapshotInstructions;

    char* init_error = g_state.api.Dart_Initialize(&params);
    if (init_error != NULL) {
      if (!dllart_is_already_initialized_error(init_error)) {
        const int rc = dllart_set_error_with_context(
            error_out, "Dart_Initialize failed", init_error);
        free(init_error);
        return rc;
      }
      free(init_error);
    }
  }

  g_state.vm_initialized = true;
  return 0;
}

static int dllart_create_isolate(DllartIsolateState* state, char** error_out) {
  if (state->isolate != NULL) {
    return 0;
  }

  {
    Dart_IsolateFlags isolate_flags;
    g_state.api.Dart_IsolateFlagsInitialize(&isolate_flags);
    isolate_flags.null_safety = true;

    char* isolate_error = NULL;
    state->isolate = g_state.api.Dart_CreateIsolateGroup(
        "dllart://module.dart", "main", kDartIsolateSnapshotData,
        kDartIsolateSnapshotInstructions, &isolate_flags, NULL, NULL,
        &isolate_error);

    if (state->isolate == NULL) {
      const int rc = dllart_set_error_with_context(
          error_out, "Dart_CreateIsolateGroup failed", isolate_error);
      free(isolate_error);
      return rc;
    }
  }

  g_state.api.Dart_ExitIsolate();
  return 0;
}

static int dllart_check_handle(Dart_Handle handle,
                               const char* context,
                               char** error_out) {
  if (!g_state.api.Dart_IsError(handle)) {
    return 0;
  }
  {
    const char* detail = g_state.api.Dart_GetError(handle);
    return dllart_set_error_with_context(error_out, context, detail);
  }
}

static size_t dllart_method_cache_limit(void) {
  const size_t limit = (size_t)DLLART_METHOD_CACHE_MAX_ENTRIES;
  if (limit == 0) {
    return 1;
  }
  return limit;
}

static int dllart_method_cache_reserve(DllartIsolateState* state,
                                       size_t needed,
                                       char** error_out) {
  if (needed <= state->method_handles_capacity) {
    return 0;
  }

  size_t next_capacity = state->method_handles_capacity == 0
                             ? 8
                             : state->method_handles_capacity * 2;
  while (next_capacity < needed) {
    next_capacity *= 2;
  }

  DllartMethodHandle* next = (DllartMethodHandle*)realloc(
      state->method_handles, next_capacity * sizeof(DllartMethodHandle));
  if (next == NULL) {
    return dllart_set_error(error_out,
                            "Out of memory while extending method cache");
  }

  state->method_handles = next;
  state->method_handles_capacity = next_capacity;
  return 0;
}

static void dllart_clear_cached_handles(DllartIsolateState* state) {
  if (g_state.api.Dart_DeletePersistentHandle != NULL) {
    if (state->root_library_handle != NULL) {
      g_state.api.Dart_DeletePersistentHandle(state->root_library_handle);
      state->root_library_handle = NULL;
    }
    if (state->dispatch_json_handle != NULL) {
      g_state.api.Dart_DeletePersistentHandle(state->dispatch_json_handle);
      state->dispatch_json_handle = NULL;
    }
    if (state->dispatch_json_batch_handle != NULL) {
      g_state.api.Dart_DeletePersistentHandle(state->dispatch_json_batch_handle);
      state->dispatch_json_batch_handle = NULL;
    }
    if (state->dispatch_json_raw_handle != NULL) {
      g_state.api.Dart_DeletePersistentHandle(state->dispatch_json_raw_handle);
      state->dispatch_json_raw_handle = NULL;
    }
    if (state->dispatch_i64_2_handle != NULL) {
      g_state.api.Dart_DeletePersistentHandle(state->dispatch_i64_2_handle);
      state->dispatch_i64_2_handle = NULL;
    }
    if (state->dispatch_i64_2_index_handle != NULL) {
      g_state.api.Dart_DeletePersistentHandle(
          state->dispatch_i64_2_index_handle);
      state->dispatch_i64_2_index_handle = NULL;
    }
    if (state->dispatch_i64_4_handle != NULL) {
      g_state.api.Dart_DeletePersistentHandle(state->dispatch_i64_4_handle);
      state->dispatch_i64_4_handle = NULL;
    }
    if (state->dispatch_i64_4_index_handle != NULL) {
      g_state.api.Dart_DeletePersistentHandle(
          state->dispatch_i64_4_index_handle);
      state->dispatch_i64_4_index_handle = NULL;
    }
    if (state->dispatch_f64_2_handle != NULL) {
      g_state.api.Dart_DeletePersistentHandle(state->dispatch_f64_2_handle);
      state->dispatch_f64_2_handle = NULL;
    }
    if (state->dispatch_f64_2_index_handle != NULL) {
      g_state.api.Dart_DeletePersistentHandle(
          state->dispatch_f64_2_index_handle);
      state->dispatch_f64_2_index_handle = NULL;
    }
    if (state->dispatch_f64_4_handle != NULL) {
      g_state.api.Dart_DeletePersistentHandle(state->dispatch_f64_4_handle);
      state->dispatch_f64_4_handle = NULL;
    }
    if (state->dispatch_f64_4_index_handle != NULL) {
      g_state.api.Dart_DeletePersistentHandle(
          state->dispatch_f64_4_index_handle);
      state->dispatch_f64_4_index_handle = NULL;
    }
    if (state->dispatch_bytes_handle != NULL) {
      g_state.api.Dart_DeletePersistentHandle(state->dispatch_bytes_handle);
      state->dispatch_bytes_handle = NULL;
    }
    if (state->dispatch_bytes_index_handle != NULL) {
      g_state.api.Dart_DeletePersistentHandle(
          state->dispatch_bytes_index_handle);
      state->dispatch_bytes_index_handle = NULL;
    }

    for (size_t i = 0; i < state->method_handles_count; i++) {
      if (state->method_handles[i].handle != NULL) {
        g_state.api.Dart_DeletePersistentHandle(state->method_handles[i].handle);
      }
      free(state->method_handles[i].method_name);
      state->method_handles[i].method_name = NULL;
      state->method_handles[i].handle = NULL;
    }
  } else {
    for (size_t i = 0; i < state->method_handles_count; i++) {
      free(state->method_handles[i].method_name);
      state->method_handles[i].method_name = NULL;
      state->method_handles[i].handle = NULL;
    }
    state->root_library_handle = NULL;
    state->dispatch_json_handle = NULL;
    state->dispatch_json_batch_handle = NULL;
    state->dispatch_json_raw_handle = NULL;
    state->dispatch_i64_2_handle = NULL;
    state->dispatch_i64_2_index_handle = NULL;
    state->dispatch_i64_4_handle = NULL;
    state->dispatch_i64_4_index_handle = NULL;
    state->dispatch_f64_2_handle = NULL;
    state->dispatch_f64_2_index_handle = NULL;
    state->dispatch_f64_4_handle = NULL;
    state->dispatch_f64_4_index_handle = NULL;
    state->dispatch_bytes_handle = NULL;
    state->dispatch_bytes_index_handle = NULL;
  }

  free(state->method_handles);
  state->method_handles = NULL;
  state->method_handles_count = 0;
  state->method_handles_capacity = 0;
}

static int dllart_prepare_cached_entrypoints(DllartIsolateState* state,
                                             char** error_out) {
  if (state->isolate == NULL) {
    return dllart_set_error(error_out,
                            "Cannot prepare dispatch handles: isolate is null");
  }
  if (state->root_library_handle != NULL &&
      state->dispatch_json_handle != NULL &&
      state->dispatch_json_batch_handle != NULL &&
      state->dispatch_json_raw_handle != NULL &&
      state->dispatch_i64_2_handle != NULL &&
      state->dispatch_i64_2_index_handle != NULL &&
      state->dispatch_i64_4_handle != NULL &&
      state->dispatch_i64_4_index_handle != NULL &&
      state->dispatch_f64_2_handle != NULL &&
      state->dispatch_f64_2_index_handle != NULL &&
      state->dispatch_f64_4_handle != NULL &&
      state->dispatch_f64_4_index_handle != NULL &&
      state->dispatch_bytes_handle != NULL &&
      state->dispatch_bytes_index_handle != NULL) {
    return 0;
  }

  Dart_PersistentHandle root_persistent = NULL;
  Dart_PersistentHandle dispatch_json_persistent = NULL;
  Dart_PersistentHandle dispatch_json_batch_persistent = NULL;
  Dart_PersistentHandle dispatch_json_raw_persistent = NULL;
  Dart_PersistentHandle dispatch_i64_2_persistent = NULL;
  Dart_PersistentHandle dispatch_i64_2_index_persistent = NULL;
  Dart_PersistentHandle dispatch_i64_4_persistent = NULL;
  Dart_PersistentHandle dispatch_i64_4_index_persistent = NULL;
  Dart_PersistentHandle dispatch_f64_2_persistent = NULL;
  Dart_PersistentHandle dispatch_f64_2_index_persistent = NULL;
  Dart_PersistentHandle dispatch_f64_4_persistent = NULL;
  Dart_PersistentHandle dispatch_f64_4_index_persistent = NULL;
  Dart_PersistentHandle dispatch_bytes_persistent = NULL;
  Dart_PersistentHandle dispatch_bytes_index_persistent = NULL;

  g_state.api.Dart_EnterIsolate(state->isolate);
  g_state.api.Dart_EnterScope();

  {
    Dart_Handle root_library = g_state.api.Dart_RootLibrary();
    if (dllart_check_handle(root_library, "Dart_RootLibrary", error_out) != 0) {
      goto fail;
    }

    Dart_Handle dispatch_json_name =
        g_state.api.Dart_NewStringFromCString("dllart_dispatch");
    if (dllart_check_handle(dispatch_json_name,
                            "Dart_NewStringFromCString(dllart_dispatch)",
                            error_out) != 0) {
      goto fail;
    }

    Dart_Handle dispatch_json_batch_name =
        g_state.api.Dart_NewStringFromCString("dllart_dispatch_batch");
    if (dllart_check_handle(dispatch_json_batch_name,
                            "Dart_NewStringFromCString(dllart_dispatch_batch)",
                            error_out) != 0) {
      goto fail;
    }

    Dart_Handle dispatch_json_raw_name =
        g_state.api.Dart_NewStringFromCString("dllart_dispatch_raw");
    if (dllart_check_handle(dispatch_json_raw_name,
                            "Dart_NewStringFromCString(dllart_dispatch_raw)",
                            error_out) != 0) {
      goto fail;
    }

    Dart_Handle dispatch_i64_2_name =
        g_state.api.Dart_NewStringFromCString("dllart_dispatch_i64_2");
    if (dllart_check_handle(dispatch_i64_2_name,
                            "Dart_NewStringFromCString(dllart_dispatch_i64_2)",
                            error_out) != 0) {
      goto fail;
    }

    Dart_Handle dispatch_i64_2_index_name =
        g_state.api.Dart_NewStringFromCString("dllart_dispatch_i64_2_index");
    if (dllart_check_handle(
            dispatch_i64_2_index_name,
            "Dart_NewStringFromCString(dllart_dispatch_i64_2_index)",
            error_out) != 0) {
      goto fail;
    }

    Dart_Handle dispatch_i64_4_name =
        g_state.api.Dart_NewStringFromCString("dllart_dispatch_i64_4");
    if (dllart_check_handle(dispatch_i64_4_name,
                            "Dart_NewStringFromCString(dllart_dispatch_i64_4)",
                            error_out) != 0) {
      goto fail;
    }

    Dart_Handle dispatch_i64_4_index_name =
        g_state.api.Dart_NewStringFromCString("dllart_dispatch_i64_4_index");
    if (dllart_check_handle(
            dispatch_i64_4_index_name,
            "Dart_NewStringFromCString(dllart_dispatch_i64_4_index)",
            error_out) != 0) {
      goto fail;
    }

    Dart_Handle dispatch_f64_2_name =
        g_state.api.Dart_NewStringFromCString("dllart_dispatch_f64_2");
    if (dllart_check_handle(dispatch_f64_2_name,
                            "Dart_NewStringFromCString(dllart_dispatch_f64_2)",
                            error_out) != 0) {
      goto fail;
    }

    Dart_Handle dispatch_f64_2_index_name =
        g_state.api.Dart_NewStringFromCString("dllart_dispatch_f64_2_index");
    if (dllart_check_handle(
            dispatch_f64_2_index_name,
            "Dart_NewStringFromCString(dllart_dispatch_f64_2_index)",
            error_out) != 0) {
      goto fail;
    }

    Dart_Handle dispatch_f64_4_name =
        g_state.api.Dart_NewStringFromCString("dllart_dispatch_f64_4");
    if (dllart_check_handle(dispatch_f64_4_name,
                            "Dart_NewStringFromCString(dllart_dispatch_f64_4)",
                            error_out) != 0) {
      goto fail;
    }

    Dart_Handle dispatch_f64_4_index_name =
        g_state.api.Dart_NewStringFromCString("dllart_dispatch_f64_4_index");
    if (dllart_check_handle(
            dispatch_f64_4_index_name,
            "Dart_NewStringFromCString(dllart_dispatch_f64_4_index)",
            error_out) != 0) {
      goto fail;
    }

    Dart_Handle dispatch_bytes_name =
        g_state.api.Dart_NewStringFromCString("dllart_dispatch_bytes");
    if (dllart_check_handle(dispatch_bytes_name,
                            "Dart_NewStringFromCString(dllart_dispatch_bytes)",
                            error_out) != 0) {
      goto fail;
    }

    Dart_Handle dispatch_bytes_index_name =
        g_state.api.Dart_NewStringFromCString("dllart_dispatch_bytes_index");
    if (dllart_check_handle(
            dispatch_bytes_index_name,
            "Dart_NewStringFromCString(dllart_dispatch_bytes_index)",
            error_out) != 0) {
      goto fail;
    }

    root_persistent = g_state.api.Dart_NewPersistentHandle(root_library);
    dispatch_json_persistent =
        g_state.api.Dart_NewPersistentHandle(dispatch_json_name);
    dispatch_json_batch_persistent =
        g_state.api.Dart_NewPersistentHandle(dispatch_json_batch_name);
    dispatch_json_raw_persistent =
        g_state.api.Dart_NewPersistentHandle(dispatch_json_raw_name);
    dispatch_i64_2_persistent =
        g_state.api.Dart_NewPersistentHandle(dispatch_i64_2_name);
    dispatch_i64_2_index_persistent =
        g_state.api.Dart_NewPersistentHandle(dispatch_i64_2_index_name);
    dispatch_i64_4_persistent =
        g_state.api.Dart_NewPersistentHandle(dispatch_i64_4_name);
    dispatch_i64_4_index_persistent =
        g_state.api.Dart_NewPersistentHandle(dispatch_i64_4_index_name);
    dispatch_f64_2_persistent =
        g_state.api.Dart_NewPersistentHandle(dispatch_f64_2_name);
    dispatch_f64_2_index_persistent =
        g_state.api.Dart_NewPersistentHandle(dispatch_f64_2_index_name);
    dispatch_f64_4_persistent =
        g_state.api.Dart_NewPersistentHandle(dispatch_f64_4_name);
    dispatch_f64_4_index_persistent =
        g_state.api.Dart_NewPersistentHandle(dispatch_f64_4_index_name);
    dispatch_bytes_persistent =
        g_state.api.Dart_NewPersistentHandle(dispatch_bytes_name);
    dispatch_bytes_index_persistent =
        g_state.api.Dart_NewPersistentHandle(dispatch_bytes_index_name);

    if (root_persistent == NULL || dispatch_json_persistent == NULL ||
        dispatch_json_batch_persistent == NULL ||
        dispatch_json_raw_persistent == NULL ||
        dispatch_i64_2_persistent == NULL ||
        dispatch_i64_2_index_persistent == NULL ||
        dispatch_i64_4_persistent == NULL ||
        dispatch_i64_4_index_persistent == NULL ||
        dispatch_f64_2_persistent == NULL ||
        dispatch_f64_2_index_persistent == NULL ||
        dispatch_f64_4_persistent == NULL ||
        dispatch_f64_4_index_persistent == NULL ||
        dispatch_bytes_persistent == NULL ||
        dispatch_bytes_index_persistent == NULL) {
      dllart_set_error(error_out,
                       "Failed to allocate persistent dispatch handles");
      goto fail;
    }
  }

  state->root_library_handle = root_persistent;
  state->dispatch_json_handle = dispatch_json_persistent;
  state->dispatch_json_batch_handle = dispatch_json_batch_persistent;
  state->dispatch_json_raw_handle = dispatch_json_raw_persistent;
  state->dispatch_i64_2_handle = dispatch_i64_2_persistent;
  state->dispatch_i64_2_index_handle = dispatch_i64_2_index_persistent;
  state->dispatch_i64_4_handle = dispatch_i64_4_persistent;
  state->dispatch_i64_4_index_handle = dispatch_i64_4_index_persistent;
  state->dispatch_f64_2_handle = dispatch_f64_2_persistent;
  state->dispatch_f64_2_index_handle = dispatch_f64_2_index_persistent;
  state->dispatch_f64_4_handle = dispatch_f64_4_persistent;
  state->dispatch_f64_4_index_handle = dispatch_f64_4_index_persistent;
  state->dispatch_bytes_handle = dispatch_bytes_persistent;
  state->dispatch_bytes_index_handle = dispatch_bytes_index_persistent;

  g_state.api.Dart_ExitScope();
  g_state.api.Dart_ExitIsolate();
  return 0;

fail:
  if (root_persistent != NULL) {
    g_state.api.Dart_DeletePersistentHandle(root_persistent);
  }
  if (dispatch_json_persistent != NULL) {
    g_state.api.Dart_DeletePersistentHandle(dispatch_json_persistent);
  }
  if (dispatch_json_batch_persistent != NULL) {
    g_state.api.Dart_DeletePersistentHandle(dispatch_json_batch_persistent);
  }
  if (dispatch_json_raw_persistent != NULL) {
    g_state.api.Dart_DeletePersistentHandle(dispatch_json_raw_persistent);
  }
  if (dispatch_i64_2_persistent != NULL) {
    g_state.api.Dart_DeletePersistentHandle(dispatch_i64_2_persistent);
  }
  if (dispatch_i64_2_index_persistent != NULL) {
    g_state.api.Dart_DeletePersistentHandle(dispatch_i64_2_index_persistent);
  }
  if (dispatch_i64_4_persistent != NULL) {
    g_state.api.Dart_DeletePersistentHandle(dispatch_i64_4_persistent);
  }
  if (dispatch_i64_4_index_persistent != NULL) {
    g_state.api.Dart_DeletePersistentHandle(dispatch_i64_4_index_persistent);
  }
  if (dispatch_f64_2_persistent != NULL) {
    g_state.api.Dart_DeletePersistentHandle(dispatch_f64_2_persistent);
  }
  if (dispatch_f64_2_index_persistent != NULL) {
    g_state.api.Dart_DeletePersistentHandle(dispatch_f64_2_index_persistent);
  }
  if (dispatch_f64_4_persistent != NULL) {
    g_state.api.Dart_DeletePersistentHandle(dispatch_f64_4_persistent);
  }
  if (dispatch_f64_4_index_persistent != NULL) {
    g_state.api.Dart_DeletePersistentHandle(dispatch_f64_4_index_persistent);
  }
  if (dispatch_bytes_persistent != NULL) {
    g_state.api.Dart_DeletePersistentHandle(dispatch_bytes_persistent);
  }
  if (dispatch_bytes_index_persistent != NULL) {
    g_state.api.Dart_DeletePersistentHandle(dispatch_bytes_index_persistent);
  }
  g_state.api.Dart_ExitScope();
  g_state.api.Dart_ExitIsolate();
  return -1;
}

static Dart_Handle dllart_method_handle_local(const char* method,
                                              DllartIsolateState* state,
                                              char** error_out) {
  size_t hit_index = SIZE_MAX;
  for (size_t i = 0; i < state->method_handles_count; i++) {
    if (strcmp(state->method_handles[i].method_name, method) == 0) {
      hit_index = i;
      break;
    }
  }

  if (hit_index != SIZE_MAX) {
    DllartMethodHandle* cached = &state->method_handles[hit_index];
    Dart_Handle local = g_state.api.Dart_HandleFromPersistent(cached->handle);
    if (dllart_check_handle(local,
                            "Dart_HandleFromPersistent(method)",
                            error_out) != 0) {
      return NULL;
    }

    // LRU update: move accessed method to the end (most recently used).
    if (hit_index + 1 < state->method_handles_count) {
      const DllartMethodHandle hit = state->method_handles[hit_index];
      memmove(&state->method_handles[hit_index],
              &state->method_handles[hit_index + 1],
              (state->method_handles_count - hit_index - 1) *
                  sizeof(DllartMethodHandle));
      state->method_handles[state->method_handles_count - 1] = hit;
    }
    return local;
  }

  const size_t max_entries = dllart_method_cache_limit();
  if (state->method_handles_count >= max_entries &&
      state->method_handles_count > 0) {
    if (state->method_handles[0].handle != NULL &&
        g_state.api.Dart_DeletePersistentHandle != NULL) {
      g_state.api.Dart_DeletePersistentHandle(state->method_handles[0].handle);
    }
    free(state->method_handles[0].method_name);
    if (state->method_handles_count > 1) {
      memmove(&state->method_handles[0],
              &state->method_handles[1],
              (state->method_handles_count - 1) * sizeof(DllartMethodHandle));
    }
    state->method_handles_count--;
  }

  Dart_Handle method_local = g_state.api.Dart_NewStringFromCString(method);
  if (dllart_check_handle(method_local,
                          "Dart_NewStringFromCString(method)",
                          error_out) != 0) {
    return NULL;
  }

  Dart_PersistentHandle method_persistent =
      g_state.api.Dart_NewPersistentHandle(method_local);
  if (method_persistent == NULL) {
    dllart_set_error(error_out,
                     "Failed to allocate persistent handle for method");
    return NULL;
  }

  if (dllart_method_cache_reserve(state, state->method_handles_count + 1, error_out) !=
      0) {
    g_state.api.Dart_DeletePersistentHandle(method_persistent);
    return NULL;
  }

  char* method_name_copy = dllart_strdup(method);
  if (method_name_copy == NULL) {
    g_state.api.Dart_DeletePersistentHandle(method_persistent);
    dllart_set_error(error_out,
                     "Out of memory while extending method cache names");
    return NULL;
  }

  state->method_handles[state->method_handles_count].method_name =
      method_name_copy;
  state->method_handles[state->method_handles_count].handle = method_persistent;
  state->method_handles_count++;

  return method_local;
}

static size_t dllart_configured_isolate_pool_size(void) {
  const char* raw = getenv("DLLART_ISOLATE_POOL_SIZE");
  if (raw == NULL || raw[0] == '\0') {
    return 1;
  }

  char* end = NULL;
  long parsed = strtol(raw, &end, 10);
  if (end == raw || *end != '\0' || parsed <= 0) {
    return 1;
  }
  if (parsed > 64) {
    parsed = 64;
  }
  return (size_t)parsed;
}

static void dllart_reset_isolate_state(DllartIsolateState* state) {
  if (state->isolate != NULL) {
    g_state.api.Dart_EnterIsolate(state->isolate);
    g_state.api.Dart_EnterScope();
    dllart_clear_cached_handles(state);
    g_state.api.Dart_ExitScope();
    g_state.api.Dart_ShutdownIsolate();
    state->isolate = NULL;
  } else {
    dllart_clear_cached_handles(state);
  }
}

static int dllart_ensure_isolate_pool(char** error_out) {
  if (g_state.isolate_count > 0 && g_state.isolates != NULL) {
    return 0;
  }

  const size_t pool_size = dllart_configured_isolate_pool_size();
  DllartIsolateState* isolates =
      (DllartIsolateState*)calloc(pool_size, sizeof(DllartIsolateState));
  if (isolates == NULL) {
    return dllart_set_error(error_out, "Out of memory while creating isolate pool");
  }

  size_t initialized = 0;
  for (size_t i = 0; i < pool_size; i++) {
    if (dllart_call_mutex_init(&isolates[i], error_out) != 0) {
      goto fail;
    }
    if (dllart_create_isolate(&isolates[i], error_out) != 0) {
      goto fail;
    }
    if (dllart_prepare_cached_entrypoints(&isolates[i], error_out) != 0) {
      goto fail;
    }
    initialized++;
  }

  g_state.isolates = isolates;
  g_state.isolate_count = pool_size;
  g_state.next_isolate_index = 0;
  return 0;

fail:
  for (size_t i = 0; i <= initialized && i < pool_size; i++) {
    if (isolates[i].call_mutex_ready) {
      dllart_reset_isolate_state(&isolates[i]);
      dllart_call_mutex_destroy(&isolates[i]);
    }
  }
  free(isolates);
  return -1;
}

static int dllart_pick_isolate_for_call(DllartIsolateState** state_out,
                                        char** error_out) {
  if (g_state.isolates == NULL || g_state.isolate_count == 0) {
    return dllart_set_not_initialized(
        error_out, "Module is not initialized. Call dllart_init first.");
  }

  const size_t index = g_state.next_isolate_index % g_state.isolate_count;
  g_state.next_isolate_index = index + 1;
  *state_out = &g_state.isolates[index];
  return 0;
}

#if !defined(_WIN32)
typedef int (*DllartThreadCallFn)(void* context);

typedef struct {
  DllartThreadCallFn fn;
  void* context;
  int status;
} DllartThreadCallState;

static _Thread_local int g_dllart_in_helper_thread = 0;

static bool dllart_stack_pointer_on_thread_stack(void) {
  volatile uint8_t stack_marker = 0;
  const uintptr_t sp = (uintptr_t)&stack_marker;
  uintptr_t low = 0;
  uintptr_t high = 0;
  size_t stack_size = 0;

#if defined(__APPLE__)
  void* stack_top = pthread_get_stackaddr_np(pthread_self());
  stack_size = pthread_get_stacksize_np(pthread_self());
  if (stack_top == NULL || stack_size == 0) {
    return true;
  }
  high = (uintptr_t)stack_top;
  low = high - stack_size;
#elif defined(__linux__)
  pthread_attr_t attr;
  if (pthread_getattr_np(pthread_self(), &attr) != 0) {
    return true;
  }
  void* stack_base = NULL;
  stack_size = 0;
  const int stack_status = pthread_attr_getstack(&attr, &stack_base, &stack_size);
  pthread_attr_destroy(&attr);
  if (stack_status != 0 || stack_base == NULL || stack_size == 0) {
    return true;
  }
  low = (uintptr_t)stack_base;
  high = low + stack_size;
#else
  return true;
#endif

  if (low > high) {
    const uintptr_t tmp = low;
    low = high;
    high = tmp;
  }
  if (!(sp >= low && sp < high)) {
    return false;
  }

  // Dart VM embedder calls are sensitive to available stack headroom.
  const uintptr_t min_headroom = 1024u * 1024u;
  if ((uintptr_t)stack_size < (2u * min_headroom)) {
    return false;
  }

  // All supported targets here use downward-growing stacks.
  if (sp < low + min_headroom) {
    return false;
  }

  return true;
}

static void* dllart_thread_call_entry(void* arg) {
  DllartThreadCallState* call = (DllartThreadCallState*)arg;
  g_dllart_in_helper_thread++;
  call->status = call->fn(call->context);
  g_dllart_in_helper_thread--;
  return NULL;
}

static int dllart_call_on_real_thread(DllartThreadCallFn fn,
                                      void* context,
                                      char** error_out) {
  pthread_attr_t attr;
  if (pthread_attr_init(&attr) != 0) {
    return dllart_set_error(error_out, "Failed to initialize helper thread attributes");
  }

  // Keep stack size comfortably above Dart embedder headroom checks.
  (void)pthread_attr_setstacksize(&attr, 4u * 1024u * 1024u);

  DllartThreadCallState call = {
      .fn = fn,
      .context = context,
      .status = -1,
  };
  pthread_t thread;
  const int create_status =
      pthread_create(&thread, &attr, dllart_thread_call_entry, &call);
  pthread_attr_destroy(&attr);
  if (create_status != 0) {
    return dllart_set_error(error_out, "Failed to create helper thread for dllart call");
  }

  const int join_status = pthread_join(thread, NULL);
  if (join_status != 0) {
    return dllart_set_error(error_out, "Failed to join helper thread for dllart call");
  }
  return call.status;
}

static bool dllart_should_proxy_thread_call(void) {
  if (g_dllart_in_helper_thread > 0) {
    return false;
  }
  const char* force = getenv("DLLART_FORCE_HELPER_THREAD");
  if (force != NULL && force[0] != '\0' && strcmp(force, "0") != 0) {
    return true;
  }
  return !dllart_stack_pointer_on_thread_stack();
}
#else
static bool dllart_should_proxy_thread_call(void) {
  return false;
}
#endif

typedef struct {
  const char* runtime_path;
  char** error_out;
} DllartInitCallContext;

typedef struct {
  const char* method;
  const char* args_json;
  char** result_json_out;
  char** error_out;
} DllartCallJsonContext;

typedef struct {
  const char* batch_json;
  char** result_json_out;
  char** error_out;
} DllartCallJsonBatchContext;

typedef struct {
  const char* method;
  int64_t a;
  int64_t b;
  int64_t* result_out;
  char** error_out;
} DllartCallI64_2Context;

typedef struct {
  int32_t method_id;
  int64_t a;
  int64_t b;
  int64_t* result_out;
  char** error_out;
} DllartCallI64_2IndexContext;

typedef struct {
  const char* method;
  int64_t a;
  int64_t b;
  int64_t c;
  int64_t d;
  int64_t* result_out;
  char** error_out;
} DllartCallI64_4Context;

typedef struct {
  int32_t method_id;
  int64_t a;
  int64_t b;
  int64_t c;
  int64_t d;
  int64_t* result_out;
  char** error_out;
} DllartCallI64_4IndexContext;

typedef struct {
  const char* method;
  double a;
  double b;
  double* result_out;
  char** error_out;
} DllartCallF64_2Context;

typedef struct {
  int32_t method_id;
  double a;
  double b;
  double* result_out;
  char** error_out;
} DllartCallF64_2IndexContext;

typedef struct {
  const char* method;
  double a;
  double b;
  double c;
  double d;
  double* result_out;
  char** error_out;
} DllartCallF64_4Context;

typedef struct {
  int32_t method_id;
  double a;
  double b;
  double c;
  double d;
  double* result_out;
  char** error_out;
} DllartCallF64_4IndexContext;

typedef struct {
  const char* method;
  const uint8_t* args;
  int32_t args_len;
  uint8_t** result_out;
  int32_t* result_len_out;
  char** error_out;
} DllartCallBytesContext;

typedef struct {
  int32_t method_id;
  const uint8_t* args;
  int32_t args_len;
  uint8_t** result_out;
  int32_t* result_len_out;
  char** error_out;
} DllartCallBytesIndexContext;

typedef struct {
  int unused;
} DllartShutdownContext;

static int dllart_init_thread_entry(void* context) {
  DllartInitCallContext* call = (DllartInitCallContext*)context;
  return dllart_init(call->runtime_path, call->error_out);
}

static int dllart_call_json_thread_entry(void* context) {
  DllartCallJsonContext* call = (DllartCallJsonContext*)context;
  return dllart_call_json(
      call->method, call->args_json, call->result_json_out, call->error_out);
}

static int dllart_call_json_batch_thread_entry(void* context) {
  DllartCallJsonBatchContext* call = (DllartCallJsonBatchContext*)context;
  return dllart_call_json_batch(
      call->batch_json, call->result_json_out, call->error_out);
}

static int dllart_call_json_raw_thread_entry(void* context) {
  DllartCallJsonContext* call = (DllartCallJsonContext*)context;
  return dllart_call_json_raw(
      call->method, call->args_json, call->result_json_out, call->error_out);
}

static int dllart_call_i64_2_thread_entry(void* context) {
  DllartCallI64_2Context* call = (DllartCallI64_2Context*)context;
  return dllart_call_i64_2(
      call->method, call->a, call->b, call->result_out, call->error_out);
}

static int dllart_call_i64_2_index_thread_entry(void* context) {
  DllartCallI64_2IndexContext* call = (DllartCallI64_2IndexContext*)context;
  return dllart_call_i64_2_index(call->method_id,
                                 call->a,
                                 call->b,
                                 call->result_out,
                                 call->error_out);
}

static int dllart_call_i64_4_thread_entry(void* context) {
  DllartCallI64_4Context* call = (DllartCallI64_4Context*)context;
  return dllart_call_i64_4(call->method,
                           call->a,
                           call->b,
                           call->c,
                           call->d,
                           call->result_out,
                           call->error_out);
}

static int dllart_call_i64_4_index_thread_entry(void* context) {
  DllartCallI64_4IndexContext* call = (DllartCallI64_4IndexContext*)context;
  return dllart_call_i64_4_index(call->method_id,
                                 call->a,
                                 call->b,
                                 call->c,
                                 call->d,
                                 call->result_out,
                                 call->error_out);
}

static int dllart_call_f64_2_thread_entry(void* context) {
  DllartCallF64_2Context* call = (DllartCallF64_2Context*)context;
  return dllart_call_f64_2(
      call->method, call->a, call->b, call->result_out, call->error_out);
}

static int dllart_call_f64_2_index_thread_entry(void* context) {
  DllartCallF64_2IndexContext* call = (DllartCallF64_2IndexContext*)context;
  return dllart_call_f64_2_index(call->method_id,
                                 call->a,
                                 call->b,
                                 call->result_out,
                                 call->error_out);
}

static int dllart_call_f64_4_thread_entry(void* context) {
  DllartCallF64_4Context* call = (DllartCallF64_4Context*)context;
  return dllart_call_f64_4(call->method,
                           call->a,
                           call->b,
                           call->c,
                           call->d,
                           call->result_out,
                           call->error_out);
}

static int dllart_call_f64_4_index_thread_entry(void* context) {
  DllartCallF64_4IndexContext* call = (DllartCallF64_4IndexContext*)context;
  return dllart_call_f64_4_index(call->method_id,
                                 call->a,
                                 call->b,
                                 call->c,
                                 call->d,
                                 call->result_out,
                                 call->error_out);
}

static int dllart_call_bytes_thread_entry(void* context) {
  DllartCallBytesContext* call = (DllartCallBytesContext*)context;
  return dllart_call_bytes(call->method,
                           call->args,
                           call->args_len,
                           call->result_out,
                           call->result_len_out,
                           call->error_out);
}

static int dllart_call_bytes_index_thread_entry(void* context) {
  DllartCallBytesIndexContext* call = (DllartCallBytesIndexContext*)context;
  return dllart_call_bytes_index(call->method_id,
                                 call->args,
                                 call->args_len,
                                 call->result_out,
                                 call->result_len_out,
                                 call->error_out);
}

static int dllart_shutdown_thread_entry(void* context) {
  (void)context;
  dllart_shutdown();
  return 0;
}

int dllart_abi_version(void) {
  return 1;
}

int dllart_init(const char* runtime_path, char** error_out) {
  if (error_out != NULL) {
    *error_out = NULL;
  }
  dllart_clear_last_error();

  if (dllart_should_proxy_thread_call()) {
#if !defined(_WIN32)
    DllartInitCallContext call = {
        .runtime_path = runtime_path,
        .error_out = error_out,
    };
    return dllart_call_on_real_thread(dllart_init_thread_entry, &call, error_out);
#endif
  }

  dllart_mutex_lock();

  int status = dllart_open_runtime(runtime_path, error_out);
  if (status == 0) {
    status = dllart_initialize_vm(error_out);
  }
  if (status == 0) {
    status = dllart_ensure_isolate_pool(error_out);
  }

  dllart_mutex_unlock();
  return status;
}

int dllart_call_json(const char* method,
                    const char* args_json,
                    char** result_json_out,
                    char** error_out) {
  int status = -1;

  if (result_json_out != NULL) {
    *result_json_out = NULL;
  }
  if (error_out != NULL) {
    *error_out = NULL;
  }
  dllart_clear_last_error();

  if (dllart_should_proxy_thread_call()) {
#if !defined(_WIN32)
    DllartCallJsonContext call = {
        .method = method,
        .args_json = args_json,
        .result_json_out = result_json_out,
        .error_out = error_out,
    };
    return dllart_call_on_real_thread(
        dllart_call_json_thread_entry, &call, error_out);
#endif
  }

  if (method == NULL || method[0] == '\0') {
    return dllart_set_invalid_argument(error_out, "Method cannot be null or empty");
  }
  if (args_json == NULL) {
    return dllart_set_invalid_argument(error_out, "args_json cannot be null");
  }
  if (dllart_validate_cstring_length(args_json,
                                     (size_t)DLLART_JSON_IN_MAX_BYTES,
                                     "args_json",
                                     error_out) != 0) {
    return -1;
  }

  DllartIsolateState* state = NULL;
  dllart_mutex_lock();
  if (dllart_pick_isolate_for_call(&state, error_out) != 0) {
    dllart_mutex_unlock();
    return -1;
  }
  dllart_call_mutex_lock(state);
  dllart_mutex_unlock();

  g_state.api.Dart_EnterIsolate(state->isolate);
  g_state.api.Dart_EnterScope();

  {
    Dart_Handle root_library =
        state->root_library_handle != NULL
            ? g_state.api.Dart_HandleFromPersistent(state->root_library_handle)
            : g_state.api.Dart_RootLibrary();
    if (dllart_check_handle(root_library, "Dart_RootLibrary", error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle dispatch_name =
        state->dispatch_json_handle != NULL
            ? g_state.api.Dart_HandleFromPersistent(state->dispatch_json_handle)
            : g_state.api.Dart_NewStringFromCString("dllart_dispatch");
    if (dllart_check_handle(dispatch_name,
                            "Dart_HandleFromPersistent(dllart_dispatch)",
                            error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle method_arg = dllart_method_handle_local(method, state, error_out);
    if (method_arg == NULL) {
      goto cleanup;
    }

    Dart_Handle payload_arg = g_state.api.Dart_NewStringFromCString(args_json);
    if (dllart_check_handle(payload_arg,
                            "Dart_NewStringFromCString(args_json)",
                            error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle call_args[2] = {method_arg, payload_arg};
    Dart_Handle result =
        g_state.api.Dart_Invoke(root_library, dispatch_name, 2, call_args);
    if (dllart_check_handle_call(result, "Dart_Invoke(dllart_dispatch)", "json",
                                 method, -1, "json", error_out) != 0) {
      goto cleanup;
    }

    const char* result_text = NULL;
    Dart_Handle as_cstr = g_state.api.Dart_StringToCString(result, &result_text);
    if (dllart_check_handle_call(as_cstr, "Dart_StringToCString(result)",
                                 "json", method, -1, "string",
                                 error_out) != 0) {
      goto cleanup;
    }

    if (strlen(result_text) > (size_t)DLLART_JSON_OUT_MAX_BYTES) {
      dllart_set_limit_exceeded(
          error_out, "result exceeds configured json_out_max_bytes");
      goto cleanup;
    }

    char* out = dllart_strdup(result_text);
    if (out == NULL) {
      dllart_set_error_code(
          error_out, DLLART_E_OOM, "Out of memory while copying result string");
      goto cleanup;
    }

    if (result_json_out != NULL) {
      *result_json_out = out;
    } else {
      free(out);
    }
  }

  status = 0;

cleanup:
  g_state.api.Dart_ExitScope();
  g_state.api.Dart_ExitIsolate();
  dllart_call_mutex_unlock(state);
  return status;
}

int dllart_call_json_batch(const char* batch_json,
                           char** result_json_out,
                           char** error_out) {
  int status = -1;

  if (result_json_out != NULL) {
    *result_json_out = NULL;
  }
  if (error_out != NULL) {
    *error_out = NULL;
  }
  dllart_clear_last_error();

  if (dllart_should_proxy_thread_call()) {
#if !defined(_WIN32)
    DllartCallJsonBatchContext call = {
        .batch_json = batch_json,
        .result_json_out = result_json_out,
        .error_out = error_out,
    };
    return dllart_call_on_real_thread(
        dllart_call_json_batch_thread_entry, &call, error_out);
#endif
  }

  if (batch_json == NULL) {
    return dllart_set_invalid_argument(error_out, "batch_json cannot be null");
  }
  if (dllart_validate_cstring_length(batch_json,
                                     (size_t)DLLART_JSON_IN_MAX_BYTES,
                                     "batch_json",
                                     error_out) != 0) {
    return -1;
  }

  DllartIsolateState* state = NULL;
  dllart_mutex_lock();
  if (dllart_pick_isolate_for_call(&state, error_out) != 0) {
    dllart_mutex_unlock();
    return -1;
  }
  dllart_call_mutex_lock(state);
  dllart_mutex_unlock();

  g_state.api.Dart_EnterIsolate(state->isolate);
  g_state.api.Dart_EnterScope();

  {
    Dart_Handle root_library =
        state->root_library_handle != NULL
            ? g_state.api.Dart_HandleFromPersistent(state->root_library_handle)
            : g_state.api.Dart_RootLibrary();
    if (dllart_check_handle(root_library, "Dart_RootLibrary", error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle dispatch_name =
        state->dispatch_json_batch_handle != NULL
            ? g_state.api.Dart_HandleFromPersistent(
                  state->dispatch_json_batch_handle)
            : g_state.api.Dart_NewStringFromCString("dllart_dispatch_batch");
    if (dllart_check_handle(dispatch_name,
                            "Dart_HandleFromPersistent(dllart_dispatch_batch)",
                            error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle payload_arg = g_state.api.Dart_NewStringFromCString(batch_json);
    if (dllart_check_handle(payload_arg,
                            "Dart_NewStringFromCString(batch_json)",
                            error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle call_args[1] = {payload_arg};
    Dart_Handle result =
        g_state.api.Dart_Invoke(root_library, dispatch_name, 1, call_args);
    if (dllart_check_handle_call(result,
                                 "Dart_Invoke(dllart_dispatch_batch)",
                                 "json_batch",
                                 "__batch__",
                                 -1,
                                 "json-array",
                                 error_out) != 0) {
      goto cleanup;
    }

    const char* result_text = NULL;
    Dart_Handle as_cstr = g_state.api.Dart_StringToCString(result, &result_text);
    if (dllart_check_handle_call(as_cstr,
                                 "Dart_StringToCString(batch_result)",
                                 "json_batch",
                                 "__batch__",
                                 -1,
                                 "string",
                                 error_out) != 0) {
      goto cleanup;
    }

    const size_t result_len = strlen(result_text);
    if (result_len > (size_t)DLLART_JSON_OUT_MAX_BYTES) {
      dllart_set_limit_exceeded(
          error_out, "batch result exceeds configured json_out_max_bytes");
      goto cleanup;
    }

    char* out = dllart_strdup(result_text);
    if (out == NULL) {
      dllart_set_error_code(
          error_out, DLLART_E_OOM, "Out of memory while copying result string");
      goto cleanup;
    }

    if (result_json_out != NULL) {
      *result_json_out = out;
    } else {
      free(out);
    }
  }

  status = 0;

cleanup:
  g_state.api.Dart_ExitScope();
  g_state.api.Dart_ExitIsolate();
  dllart_call_mutex_unlock(state);
  return status;
}

int dllart_call_json_raw(const char* method,
                         const char* args_json,
                         char** result_json_out,
                         char** error_out) {
  int status = -1;

  if (result_json_out != NULL) {
    *result_json_out = NULL;
  }
  if (error_out != NULL) {
    *error_out = NULL;
  }
  dllart_clear_last_error();

  if (dllart_should_proxy_thread_call()) {
#if !defined(_WIN32)
    DllartCallJsonContext call = {
        .method = method,
        .args_json = args_json,
        .result_json_out = result_json_out,
        .error_out = error_out,
    };
    return dllart_call_on_real_thread(
        dllart_call_json_raw_thread_entry, &call, error_out);
#endif
  }

  if (method == NULL || method[0] == '\0') {
    return dllart_set_invalid_argument(error_out, "Method cannot be null or empty");
  }
  if (args_json == NULL) {
    return dllart_set_invalid_argument(error_out, "args_json cannot be null");
  }
  if (dllart_validate_cstring_length(args_json,
                                     (size_t)DLLART_JSON_IN_MAX_BYTES,
                                     "args_json",
                                     error_out) != 0) {
    return -1;
  }

  DllartIsolateState* state = NULL;
  dllart_mutex_lock();
  if (dllart_pick_isolate_for_call(&state, error_out) != 0) {
    dllart_mutex_unlock();
    return -1;
  }
  dllart_call_mutex_lock(state);
  dllart_mutex_unlock();

  g_state.api.Dart_EnterIsolate(state->isolate);
  g_state.api.Dart_EnterScope();

  {
    Dart_Handle root_library =
        state->root_library_handle != NULL
            ? g_state.api.Dart_HandleFromPersistent(state->root_library_handle)
            : g_state.api.Dart_RootLibrary();
    if (dllart_check_handle(root_library, "Dart_RootLibrary", error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle dispatch_name =
        state->dispatch_json_raw_handle != NULL
            ? g_state.api.Dart_HandleFromPersistent(
                  state->dispatch_json_raw_handle)
            : g_state.api.Dart_NewStringFromCString("dllart_dispatch_raw");
    if (dllart_check_handle(dispatch_name,
                            "Dart_HandleFromPersistent(dllart_dispatch_raw)",
                            error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle method_arg = dllart_method_handle_local(method, state, error_out);
    if (method_arg == NULL) {
      goto cleanup;
    }

    Dart_Handle payload_arg = g_state.api.Dart_NewStringFromCString(args_json);
    if (dllart_check_handle(payload_arg,
                            "Dart_NewStringFromCString(args_json)",
                            error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle call_args[2] = {method_arg, payload_arg};
    Dart_Handle result =
        g_state.api.Dart_Invoke(root_library, dispatch_name, 2, call_args);
    if (dllart_check_handle_call(result, "Dart_Invoke(dllart_dispatch_raw)",
                                 "json_raw", method, -1, "json",
                                 error_out) != 0) {
      goto cleanup;
    }

    const char* result_text = NULL;
    Dart_Handle as_cstr = g_state.api.Dart_StringToCString(result, &result_text);
    if (dllart_check_handle_call(as_cstr, "Dart_StringToCString(result)",
                                 "json_raw", method, -1, "string",
                                 error_out) != 0) {
      goto cleanup;
    }

    if (strlen(result_text) > (size_t)DLLART_JSON_OUT_MAX_BYTES) {
      dllart_set_limit_exceeded(
          error_out, "result exceeds configured json_out_max_bytes");
      goto cleanup;
    }

    char* out = dllart_strdup(result_text);
    if (out == NULL) {
      dllart_set_error_code(
          error_out, DLLART_E_OOM, "Out of memory while copying result string");
      goto cleanup;
    }

    if (result_json_out != NULL) {
      *result_json_out = out;
    } else {
      free(out);
    }
  }

  status = 0;

cleanup:
  g_state.api.Dart_ExitScope();
  g_state.api.Dart_ExitIsolate();
  dllart_call_mutex_unlock(state);
  return status;
}

int dllart_call_i64_2(const char* method,
                      int64_t a,
                      int64_t b,
                      int64_t* result_out,
                      char** error_out) {
  int status = -1;

  if (result_out != NULL) {
    *result_out = 0;
  }
  if (error_out != NULL) {
    *error_out = NULL;
  }
  dllart_clear_last_error();

  if (dllart_should_proxy_thread_call()) {
#if !defined(_WIN32)
    DllartCallI64_2Context call = {
        .method = method,
        .a = a,
        .b = b,
        .result_out = result_out,
        .error_out = error_out,
    };
    return dllart_call_on_real_thread(
        dllart_call_i64_2_thread_entry, &call, error_out);
#endif
  }

  if (method == NULL || method[0] == '\0') {
    return dllart_set_invalid_argument(error_out, "Method cannot be null or empty");
  }

  DllartIsolateState* state = NULL;
  dllart_mutex_lock();
  if (dllart_pick_isolate_for_call(&state, error_out) != 0) {
    dllart_mutex_unlock();
    return -1;
  }
  dllart_call_mutex_lock(state);
  dllart_mutex_unlock();

  g_state.api.Dart_EnterIsolate(state->isolate);
  g_state.api.Dart_EnterScope();

  {
    Dart_Handle root_library =
        state->root_library_handle != NULL
            ? g_state.api.Dart_HandleFromPersistent(state->root_library_handle)
            : g_state.api.Dart_RootLibrary();
    if (dllart_check_handle(root_library, "Dart_RootLibrary", error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle dispatch_name =
        state->dispatch_i64_2_handle != NULL
            ? g_state.api.Dart_HandleFromPersistent(state->dispatch_i64_2_handle)
            : g_state.api.Dart_NewStringFromCString("dllart_dispatch_i64_2");
    if (dllart_check_handle(dispatch_name,
                            "Dart_HandleFromPersistent(dllart_dispatch_i64_2)",
                            error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle method_arg = dllart_method_handle_local(method, state, error_out);
    if (method_arg == NULL) {
      goto cleanup;
    }

    Dart_Handle a_arg = g_state.api.Dart_NewInteger(a);
    if (dllart_check_handle(a_arg, "Dart_NewInteger(a)", error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle b_arg = g_state.api.Dart_NewInteger(b);
    if (dllart_check_handle(b_arg, "Dart_NewInteger(b)", error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle call_args[3] = {method_arg, a_arg, b_arg};
    Dart_Handle result =
        g_state.api.Dart_Invoke(root_library, dispatch_name, 3, call_args);
    if (dllart_check_handle_call(result, "Dart_Invoke(dllart_dispatch_i64_2)",
                                 "i64_2", method, -1, "int64,int64",
                                 error_out) != 0) {
      goto cleanup;
    }

    int64_t result_value = 0;
    Dart_Handle as_i64 = g_state.api.Dart_IntegerToInt64(result, &result_value);
    if (dllart_check_handle_call(as_i64, "Dart_IntegerToInt64(result)", "i64_2",
                                 method, -1, "int64", error_out) != 0) {
      goto cleanup;
    }

    if (result_out != NULL) {
      *result_out = result_value;
    }
  }

  status = 0;

cleanup:
  g_state.api.Dart_ExitScope();
  g_state.api.Dart_ExitIsolate();
  dllart_call_mutex_unlock(state);
  return status;
}

int dllart_call_i64_2_index(int32_t method_id,
                            int64_t a,
                            int64_t b,
                            int64_t* result_out,
                            char** error_out) {
  int status = -1;

  if (result_out != NULL) {
    *result_out = 0;
  }
  if (error_out != NULL) {
    *error_out = NULL;
  }
  dllart_clear_last_error();

  if (dllart_should_proxy_thread_call()) {
#if !defined(_WIN32)
    DllartCallI64_2IndexContext call = {
        .method_id = method_id,
        .a = a,
        .b = b,
        .result_out = result_out,
        .error_out = error_out,
    };
    return dllart_call_on_real_thread(
        dllart_call_i64_2_index_thread_entry, &call, error_out);
#endif
  }

  if (method_id < 0) {
    return dllart_set_invalid_argument(error_out, "method_id cannot be negative");
  }

  DllartIsolateState* state = NULL;
  dllart_mutex_lock();
  if (dllart_pick_isolate_for_call(&state, error_out) != 0) {
    dllart_mutex_unlock();
    return -1;
  }
  dllart_call_mutex_lock(state);
  dllart_mutex_unlock();

  g_state.api.Dart_EnterIsolate(state->isolate);
  g_state.api.Dart_EnterScope();

  {
    Dart_Handle root_library =
        state->root_library_handle != NULL
            ? g_state.api.Dart_HandleFromPersistent(state->root_library_handle)
            : g_state.api.Dart_RootLibrary();
    if (dllart_check_handle(root_library, "Dart_RootLibrary", error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle dispatch_name =
        state->dispatch_i64_2_index_handle != NULL
            ? g_state.api.Dart_HandleFromPersistent(
                  state->dispatch_i64_2_index_handle)
            : g_state.api.Dart_NewStringFromCString(
                  "dllart_dispatch_i64_2_index");
    if (dllart_check_handle(
            dispatch_name,
            "Dart_HandleFromPersistent(dllart_dispatch_i64_2_index)",
            error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle method_id_arg = g_state.api.Dart_NewInteger(method_id);
    if (dllart_check_handle(method_id_arg,
                            "Dart_NewInteger(method_id)",
                            error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle a_arg = g_state.api.Dart_NewInteger(a);
    if (dllart_check_handle(a_arg, "Dart_NewInteger(a)", error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle b_arg = g_state.api.Dart_NewInteger(b);
    if (dllart_check_handle(b_arg, "Dart_NewInteger(b)", error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle call_args[3] = {method_id_arg, a_arg, b_arg};
    Dart_Handle result =
        g_state.api.Dart_Invoke(root_library, dispatch_name, 3, call_args);
    if (dllart_check_handle_call(result,
                                 "Dart_Invoke(dllart_dispatch_i64_2_index)",
                                 "i64_2_index", NULL, method_id,
                                 "int64,int64", error_out) != 0) {
      goto cleanup;
    }

    int64_t result_value = 0;
    Dart_Handle as_i64 = g_state.api.Dart_IntegerToInt64(result, &result_value);
    if (dllart_check_handle_call(as_i64, "Dart_IntegerToInt64(result)",
                                 "i64_2_index", NULL, method_id, "int64",
                                 error_out) != 0) {
      goto cleanup;
    }

    if (result_out != NULL) {
      *result_out = result_value;
    }
  }

  status = 0;

cleanup:
  g_state.api.Dart_ExitScope();
  g_state.api.Dart_ExitIsolate();
  dllart_call_mutex_unlock(state);
  return status;
}

int dllart_call_i64_4(const char* method,
                      int64_t a,
                      int64_t b,
                      int64_t c,
                      int64_t d,
                      int64_t* result_out,
                      char** error_out) {
  int status = -1;

  if (result_out != NULL) {
    *result_out = 0;
  }
  if (error_out != NULL) {
    *error_out = NULL;
  }
  dllart_clear_last_error();

  if (dllart_should_proxy_thread_call()) {
#if !defined(_WIN32)
    DllartCallI64_4Context call = {
        .method = method,
        .a = a,
        .b = b,
        .c = c,
        .d = d,
        .result_out = result_out,
        .error_out = error_out,
    };
    return dllart_call_on_real_thread(
        dllart_call_i64_4_thread_entry, &call, error_out);
#endif
  }

  if (method == NULL || method[0] == '\0') {
    return dllart_set_invalid_argument(error_out, "Method cannot be null or empty");
  }

  DllartIsolateState* state = NULL;
  dllart_mutex_lock();
  if (dllart_pick_isolate_for_call(&state, error_out) != 0) {
    dllart_mutex_unlock();
    return -1;
  }
  dllart_call_mutex_lock(state);
  dllart_mutex_unlock();

  g_state.api.Dart_EnterIsolate(state->isolate);
  g_state.api.Dart_EnterScope();

  {
    Dart_Handle root_library =
        state->root_library_handle != NULL
            ? g_state.api.Dart_HandleFromPersistent(state->root_library_handle)
            : g_state.api.Dart_RootLibrary();
    if (dllart_check_handle(root_library, "Dart_RootLibrary", error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle dispatch_name =
        state->dispatch_i64_4_handle != NULL
            ? g_state.api.Dart_HandleFromPersistent(state->dispatch_i64_4_handle)
            : g_state.api.Dart_NewStringFromCString("dllart_dispatch_i64_4");
    if (dllart_check_handle(dispatch_name,
                            "Dart_HandleFromPersistent(dllart_dispatch_i64_4)",
                            error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle method_arg = dllart_method_handle_local(method, state, error_out);
    if (method_arg == NULL) {
      goto cleanup;
    }

    Dart_Handle a_arg = g_state.api.Dart_NewInteger(a);
    if (dllart_check_handle(a_arg, "Dart_NewInteger(a)", error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle b_arg = g_state.api.Dart_NewInteger(b);
    if (dllart_check_handle(b_arg, "Dart_NewInteger(b)", error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle c_arg = g_state.api.Dart_NewInteger(c);
    if (dllart_check_handle(c_arg, "Dart_NewInteger(c)", error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle d_arg = g_state.api.Dart_NewInteger(d);
    if (dllart_check_handle(d_arg, "Dart_NewInteger(d)", error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle call_args[5] = {method_arg, a_arg, b_arg, c_arg, d_arg};
    Dart_Handle result =
        g_state.api.Dart_Invoke(root_library, dispatch_name, 5, call_args);
    if (dllart_check_handle_call(result, "Dart_Invoke(dllart_dispatch_i64_4)",
                                 "i64_4", method, -1,
                                 "int64,int64,int64,int64", error_out) != 0) {
      goto cleanup;
    }

    int64_t result_value = 0;
    Dart_Handle as_i64 = g_state.api.Dart_IntegerToInt64(result, &result_value);
    if (dllart_check_handle_call(as_i64, "Dart_IntegerToInt64(result)", "i64_4",
                                 method, -1, "int64", error_out) != 0) {
      goto cleanup;
    }

    if (result_out != NULL) {
      *result_out = result_value;
    }
  }

  status = 0;

cleanup:
  g_state.api.Dart_ExitScope();
  g_state.api.Dart_ExitIsolate();
  dllart_call_mutex_unlock(state);
  return status;
}

int dllart_call_i64_4_index(int32_t method_id,
                            int64_t a,
                            int64_t b,
                            int64_t c,
                            int64_t d,
                            int64_t* result_out,
                            char** error_out) {
  int status = -1;

  if (result_out != NULL) {
    *result_out = 0;
  }
  if (error_out != NULL) {
    *error_out = NULL;
  }
  dllart_clear_last_error();

  if (dllart_should_proxy_thread_call()) {
#if !defined(_WIN32)
    DllartCallI64_4IndexContext call = {
        .method_id = method_id,
        .a = a,
        .b = b,
        .c = c,
        .d = d,
        .result_out = result_out,
        .error_out = error_out,
    };
    return dllart_call_on_real_thread(
        dllart_call_i64_4_index_thread_entry, &call, error_out);
#endif
  }

  if (method_id < 0) {
    return dllart_set_invalid_argument(error_out, "method_id cannot be negative");
  }

  DllartIsolateState* state = NULL;
  dllart_mutex_lock();
  if (dllart_pick_isolate_for_call(&state, error_out) != 0) {
    dllart_mutex_unlock();
    return -1;
  }
  dllart_call_mutex_lock(state);
  dllart_mutex_unlock();

  g_state.api.Dart_EnterIsolate(state->isolate);
  g_state.api.Dart_EnterScope();

  {
    Dart_Handle root_library =
        state->root_library_handle != NULL
            ? g_state.api.Dart_HandleFromPersistent(state->root_library_handle)
            : g_state.api.Dart_RootLibrary();
    if (dllart_check_handle(root_library, "Dart_RootLibrary", error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle dispatch_name =
        state->dispatch_i64_4_index_handle != NULL
            ? g_state.api.Dart_HandleFromPersistent(
                  state->dispatch_i64_4_index_handle)
            : g_state.api.Dart_NewStringFromCString(
                  "dllart_dispatch_i64_4_index");
    if (dllart_check_handle(
            dispatch_name,
            "Dart_HandleFromPersistent(dllart_dispatch_i64_4_index)",
            error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle method_id_arg = g_state.api.Dart_NewInteger(method_id);
    if (dllart_check_handle(method_id_arg,
                            "Dart_NewInteger(method_id)",
                            error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle a_arg = g_state.api.Dart_NewInteger(a);
    if (dllart_check_handle(a_arg, "Dart_NewInteger(a)", error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle b_arg = g_state.api.Dart_NewInteger(b);
    if (dllart_check_handle(b_arg, "Dart_NewInteger(b)", error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle c_arg = g_state.api.Dart_NewInteger(c);
    if (dllart_check_handle(c_arg, "Dart_NewInteger(c)", error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle d_arg = g_state.api.Dart_NewInteger(d);
    if (dllart_check_handle(d_arg, "Dart_NewInteger(d)", error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle call_args[5] = {method_id_arg, a_arg, b_arg, c_arg, d_arg};
    Dart_Handle result =
        g_state.api.Dart_Invoke(root_library, dispatch_name, 5, call_args);
    if (dllart_check_handle_call(result,
                                 "Dart_Invoke(dllart_dispatch_i64_4_index)",
                                 "i64_4_index", NULL, method_id,
                                 "int64,int64,int64,int64",
                                 error_out) != 0) {
      goto cleanup;
    }

    int64_t result_value = 0;
    Dart_Handle as_i64 = g_state.api.Dart_IntegerToInt64(result, &result_value);
    if (dllart_check_handle_call(as_i64, "Dart_IntegerToInt64(result)",
                                 "i64_4_index", NULL, method_id, "int64",
                                 error_out) != 0) {
      goto cleanup;
    }

    if (result_out != NULL) {
      *result_out = result_value;
    }
  }

  status = 0;

cleanup:
  g_state.api.Dart_ExitScope();
  g_state.api.Dart_ExitIsolate();
  dllart_call_mutex_unlock(state);
  return status;
}

int dllart_call_f64_2(const char* method,
                      double a,
                      double b,
                      double* result_out,
                      char** error_out) {
  int status = -1;

  if (result_out != NULL) {
    *result_out = 0.0;
  }
  if (error_out != NULL) {
    *error_out = NULL;
  }
  dllart_clear_last_error();

  if (dllart_should_proxy_thread_call()) {
#if !defined(_WIN32)
    DllartCallF64_2Context call = {
        .method = method,
        .a = a,
        .b = b,
        .result_out = result_out,
        .error_out = error_out,
    };
    return dllart_call_on_real_thread(
        dllart_call_f64_2_thread_entry, &call, error_out);
#endif
  }

  if (method == NULL || method[0] == '\0') {
    return dllart_set_invalid_argument(error_out, "Method cannot be null or empty");
  }

  DllartIsolateState* state = NULL;
  dllart_mutex_lock();
  if (dllart_pick_isolate_for_call(&state, error_out) != 0) {
    dllart_mutex_unlock();
    return -1;
  }
  dllart_call_mutex_lock(state);
  dllart_mutex_unlock();

  g_state.api.Dart_EnterIsolate(state->isolate);
  g_state.api.Dart_EnterScope();

  {
    Dart_Handle root_library =
        state->root_library_handle != NULL
            ? g_state.api.Dart_HandleFromPersistent(state->root_library_handle)
            : g_state.api.Dart_RootLibrary();
    if (dllart_check_handle(root_library, "Dart_RootLibrary", error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle dispatch_name =
        state->dispatch_f64_2_handle != NULL
            ? g_state.api.Dart_HandleFromPersistent(state->dispatch_f64_2_handle)
            : g_state.api.Dart_NewStringFromCString("dllart_dispatch_f64_2");
    if (dllart_check_handle(dispatch_name,
                            "Dart_HandleFromPersistent(dllart_dispatch_f64_2)",
                            error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle method_arg = dllart_method_handle_local(method, state, error_out);
    if (method_arg == NULL) {
      goto cleanup;
    }

    Dart_Handle a_arg = g_state.api.Dart_NewDouble(a);
    if (dllart_check_handle(a_arg, "Dart_NewDouble(a)", error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle b_arg = g_state.api.Dart_NewDouble(b);
    if (dllart_check_handle(b_arg, "Dart_NewDouble(b)", error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle call_args[3] = {method_arg, a_arg, b_arg};
    Dart_Handle result =
        g_state.api.Dart_Invoke(root_library, dispatch_name, 3, call_args);
    if (dllart_check_handle_call(result, "Dart_Invoke(dllart_dispatch_f64_2)",
                                 "f64_2", method, -1, "double,double",
                                 error_out) != 0) {
      goto cleanup;
    }

    double result_value = 0.0;
    Dart_Handle as_f64 = g_state.api.Dart_DoubleValue(result, &result_value);
    if (dllart_check_handle_call(as_f64, "Dart_DoubleValue(result)", "f64_2",
                                 method, -1, "double", error_out) != 0) {
      goto cleanup;
    }

    if (result_out != NULL) {
      *result_out = result_value;
    }
  }

  status = 0;

cleanup:
  g_state.api.Dart_ExitScope();
  g_state.api.Dart_ExitIsolate();
  dllart_call_mutex_unlock(state);
  return status;
}

int dllart_call_f64_2_index(int32_t method_id,
                            double a,
                            double b,
                            double* result_out,
                            char** error_out) {
  int status = -1;

  if (result_out != NULL) {
    *result_out = 0.0;
  }
  if (error_out != NULL) {
    *error_out = NULL;
  }
  dllart_clear_last_error();

  if (dllart_should_proxy_thread_call()) {
#if !defined(_WIN32)
    DllartCallF64_2IndexContext call = {
        .method_id = method_id,
        .a = a,
        .b = b,
        .result_out = result_out,
        .error_out = error_out,
    };
    return dllart_call_on_real_thread(
        dllart_call_f64_2_index_thread_entry, &call, error_out);
#endif
  }

  if (method_id < 0) {
    return dllart_set_invalid_argument(error_out, "method_id cannot be negative");
  }

  DllartIsolateState* state = NULL;
  dllart_mutex_lock();
  if (dllart_pick_isolate_for_call(&state, error_out) != 0) {
    dllart_mutex_unlock();
    return -1;
  }
  dllart_call_mutex_lock(state);
  dllart_mutex_unlock();

  g_state.api.Dart_EnterIsolate(state->isolate);
  g_state.api.Dart_EnterScope();

  {
    Dart_Handle root_library =
        state->root_library_handle != NULL
            ? g_state.api.Dart_HandleFromPersistent(state->root_library_handle)
            : g_state.api.Dart_RootLibrary();
    if (dllart_check_handle(root_library, "Dart_RootLibrary", error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle dispatch_name =
        state->dispatch_f64_2_index_handle != NULL
            ? g_state.api.Dart_HandleFromPersistent(
                  state->dispatch_f64_2_index_handle)
            : g_state.api.Dart_NewStringFromCString(
                  "dllart_dispatch_f64_2_index");
    if (dllart_check_handle(
            dispatch_name,
            "Dart_HandleFromPersistent(dllart_dispatch_f64_2_index)",
            error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle method_id_arg = g_state.api.Dart_NewInteger(method_id);
    if (dllart_check_handle(method_id_arg,
                            "Dart_NewInteger(method_id)",
                            error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle a_arg = g_state.api.Dart_NewDouble(a);
    if (dllart_check_handle(a_arg, "Dart_NewDouble(a)", error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle b_arg = g_state.api.Dart_NewDouble(b);
    if (dllart_check_handle(b_arg, "Dart_NewDouble(b)", error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle call_args[3] = {method_id_arg, a_arg, b_arg};
    Dart_Handle result =
        g_state.api.Dart_Invoke(root_library, dispatch_name, 3, call_args);
    if (dllart_check_handle_call(result,
                                 "Dart_Invoke(dllart_dispatch_f64_2_index)",
                                 "f64_2_index", NULL, method_id,
                                 "double,double", error_out) != 0) {
      goto cleanup;
    }

    double result_value = 0.0;
    Dart_Handle as_f64 = g_state.api.Dart_DoubleValue(result, &result_value);
    if (dllart_check_handle_call(as_f64, "Dart_DoubleValue(result)",
                                 "f64_2_index", NULL, method_id, "double",
                                 error_out) != 0) {
      goto cleanup;
    }

    if (result_out != NULL) {
      *result_out = result_value;
    }
  }

  status = 0;

cleanup:
  g_state.api.Dart_ExitScope();
  g_state.api.Dart_ExitIsolate();
  dllart_call_mutex_unlock(state);
  return status;
}

int dllart_call_f64_4(const char* method,
                      double a,
                      double b,
                      double c,
                      double d,
                      double* result_out,
                      char** error_out) {
  int status = -1;

  if (result_out != NULL) {
    *result_out = 0.0;
  }
  if (error_out != NULL) {
    *error_out = NULL;
  }
  dllart_clear_last_error();

  if (dllart_should_proxy_thread_call()) {
#if !defined(_WIN32)
    DllartCallF64_4Context call = {
        .method = method,
        .a = a,
        .b = b,
        .c = c,
        .d = d,
        .result_out = result_out,
        .error_out = error_out,
    };
    return dllart_call_on_real_thread(
        dllart_call_f64_4_thread_entry, &call, error_out);
#endif
  }

  if (method == NULL || method[0] == '\0') {
    return dllart_set_invalid_argument(error_out, "Method cannot be null or empty");
  }

  DllartIsolateState* state = NULL;
  dllart_mutex_lock();
  if (dllart_pick_isolate_for_call(&state, error_out) != 0) {
    dllart_mutex_unlock();
    return -1;
  }
  dllart_call_mutex_lock(state);
  dllart_mutex_unlock();

  g_state.api.Dart_EnterIsolate(state->isolate);
  g_state.api.Dart_EnterScope();

  {
    Dart_Handle root_library =
        state->root_library_handle != NULL
            ? g_state.api.Dart_HandleFromPersistent(state->root_library_handle)
            : g_state.api.Dart_RootLibrary();
    if (dllart_check_handle(root_library, "Dart_RootLibrary", error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle dispatch_name =
        state->dispatch_f64_4_handle != NULL
            ? g_state.api.Dart_HandleFromPersistent(state->dispatch_f64_4_handle)
            : g_state.api.Dart_NewStringFromCString("dllart_dispatch_f64_4");
    if (dllart_check_handle(dispatch_name,
                            "Dart_HandleFromPersistent(dllart_dispatch_f64_4)",
                            error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle method_arg = dllart_method_handle_local(method, state, error_out);
    if (method_arg == NULL) {
      goto cleanup;
    }

    Dart_Handle a_arg = g_state.api.Dart_NewDouble(a);
    if (dllart_check_handle(a_arg, "Dart_NewDouble(a)", error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle b_arg = g_state.api.Dart_NewDouble(b);
    if (dllart_check_handle(b_arg, "Dart_NewDouble(b)", error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle c_arg = g_state.api.Dart_NewDouble(c);
    if (dllart_check_handle(c_arg, "Dart_NewDouble(c)", error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle d_arg = g_state.api.Dart_NewDouble(d);
    if (dllart_check_handle(d_arg, "Dart_NewDouble(d)", error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle call_args[5] = {method_arg, a_arg, b_arg, c_arg, d_arg};
    Dart_Handle result =
        g_state.api.Dart_Invoke(root_library, dispatch_name, 5, call_args);
    if (dllart_check_handle_call(result, "Dart_Invoke(dllart_dispatch_f64_4)",
                                 "f64_4", method, -1,
                                 "double,double,double,double",
                                 error_out) != 0) {
      goto cleanup;
    }

    double result_value = 0.0;
    Dart_Handle as_f64 = g_state.api.Dart_DoubleValue(result, &result_value);
    if (dllart_check_handle_call(as_f64, "Dart_DoubleValue(result)", "f64_4",
                                 method, -1, "double", error_out) != 0) {
      goto cleanup;
    }

    if (result_out != NULL) {
      *result_out = result_value;
    }
  }

  status = 0;

cleanup:
  g_state.api.Dart_ExitScope();
  g_state.api.Dart_ExitIsolate();
  dllart_call_mutex_unlock(state);
  return status;
}

int dllart_call_f64_4_index(int32_t method_id,
                            double a,
                            double b,
                            double c,
                            double d,
                            double* result_out,
                            char** error_out) {
  int status = -1;

  if (result_out != NULL) {
    *result_out = 0.0;
  }
  if (error_out != NULL) {
    *error_out = NULL;
  }
  dllart_clear_last_error();

  if (dllart_should_proxy_thread_call()) {
#if !defined(_WIN32)
    DllartCallF64_4IndexContext call = {
        .method_id = method_id,
        .a = a,
        .b = b,
        .c = c,
        .d = d,
        .result_out = result_out,
        .error_out = error_out,
    };
    return dllart_call_on_real_thread(
        dllart_call_f64_4_index_thread_entry, &call, error_out);
#endif
  }

  if (method_id < 0) {
    return dllart_set_invalid_argument(error_out, "method_id cannot be negative");
  }

  DllartIsolateState* state = NULL;
  dllart_mutex_lock();
  if (dllart_pick_isolate_for_call(&state, error_out) != 0) {
    dllart_mutex_unlock();
    return -1;
  }
  dllart_call_mutex_lock(state);
  dllart_mutex_unlock();

  g_state.api.Dart_EnterIsolate(state->isolate);
  g_state.api.Dart_EnterScope();

  {
    Dart_Handle root_library =
        state->root_library_handle != NULL
            ? g_state.api.Dart_HandleFromPersistent(state->root_library_handle)
            : g_state.api.Dart_RootLibrary();
    if (dllart_check_handle(root_library, "Dart_RootLibrary", error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle dispatch_name =
        state->dispatch_f64_4_index_handle != NULL
            ? g_state.api.Dart_HandleFromPersistent(
                  state->dispatch_f64_4_index_handle)
            : g_state.api.Dart_NewStringFromCString(
                  "dllart_dispatch_f64_4_index");
    if (dllart_check_handle(
            dispatch_name,
            "Dart_HandleFromPersistent(dllart_dispatch_f64_4_index)",
            error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle method_id_arg = g_state.api.Dart_NewInteger(method_id);
    if (dllart_check_handle(method_id_arg,
                            "Dart_NewInteger(method_id)",
                            error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle a_arg = g_state.api.Dart_NewDouble(a);
    if (dllart_check_handle(a_arg, "Dart_NewDouble(a)", error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle b_arg = g_state.api.Dart_NewDouble(b);
    if (dllart_check_handle(b_arg, "Dart_NewDouble(b)", error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle c_arg = g_state.api.Dart_NewDouble(c);
    if (dllart_check_handle(c_arg, "Dart_NewDouble(c)", error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle d_arg = g_state.api.Dart_NewDouble(d);
    if (dllart_check_handle(d_arg, "Dart_NewDouble(d)", error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle call_args[5] = {method_id_arg, a_arg, b_arg, c_arg, d_arg};
    Dart_Handle result =
        g_state.api.Dart_Invoke(root_library, dispatch_name, 5, call_args);
    if (dllart_check_handle_call(result,
                                 "Dart_Invoke(dllart_dispatch_f64_4_index)",
                                 "f64_4_index", NULL, method_id,
                                 "double,double,double,double",
                                 error_out) != 0) {
      goto cleanup;
    }

    double result_value = 0.0;
    Dart_Handle as_f64 = g_state.api.Dart_DoubleValue(result, &result_value);
    if (dllart_check_handle_call(as_f64, "Dart_DoubleValue(result)",
                                 "f64_4_index", NULL, method_id, "double",
                                 error_out) != 0) {
      goto cleanup;
    }

    if (result_out != NULL) {
      *result_out = result_value;
    }
  }

  status = 0;

cleanup:
  g_state.api.Dart_ExitScope();
  g_state.api.Dart_ExitIsolate();
  dllart_call_mutex_unlock(state);
  return status;
}

int dllart_call_bytes(const char* method,
                      const uint8_t* args,
                      int32_t args_len,
                      uint8_t** result_out,
                      int32_t* result_len_out,
                      char** error_out) {
  int status = -1;

  if (result_out != NULL) {
    *result_out = NULL;
  }
  if (result_len_out != NULL) {
    *result_len_out = 0;
  }
  if (error_out != NULL) {
    *error_out = NULL;
  }
  dllart_clear_last_error();

  if (dllart_should_proxy_thread_call()) {
#if !defined(_WIN32)
    DllartCallBytesContext call = {
        .method = method,
        .args = args,
        .args_len = args_len,
        .result_out = result_out,
        .result_len_out = result_len_out,
        .error_out = error_out,
    };
    return dllart_call_on_real_thread(
        dllart_call_bytes_thread_entry, &call, error_out);
#endif
  }

  if (method == NULL || method[0] == '\0') {
    return dllart_set_invalid_argument(error_out, "Method cannot be null or empty");
  }
  if (args_len < 0) {
    return dllart_set_invalid_argument(error_out, "args_len cannot be negative");
  }
  if (args_len > 0 && args == NULL) {
    return dllart_set_invalid_argument(error_out, "args cannot be null when args_len > 0");
  }
  if ((size_t)args_len > (size_t)DLLART_BYTES_IN_MAX_BYTES) {
    return dllart_set_limit_exceeded(
        error_out, "args exceeds configured bytes_in_max_bytes");
  }

  DllartIsolateState* state = NULL;
  dllart_mutex_lock();
  if (dllart_pick_isolate_for_call(&state, error_out) != 0) {
    dllart_mutex_unlock();
    return -1;
  }
  dllart_call_mutex_lock(state);
  dllart_mutex_unlock();

  g_state.api.Dart_EnterIsolate(state->isolate);
  g_state.api.Dart_EnterScope();

  {
    Dart_Handle root_library =
        state->root_library_handle != NULL
            ? g_state.api.Dart_HandleFromPersistent(state->root_library_handle)
            : g_state.api.Dart_RootLibrary();
    if (dllart_check_handle(root_library, "Dart_RootLibrary", error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle dispatch_name =
        state->dispatch_bytes_handle != NULL
            ? g_state.api.Dart_HandleFromPersistent(state->dispatch_bytes_handle)
            : g_state.api.Dart_NewStringFromCString("dllart_dispatch_bytes");
    if (dllart_check_handle(dispatch_name,
                            "Dart_HandleFromPersistent(dllart_dispatch_bytes)",
                            error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle method_arg = dllart_method_handle_local(method, state, error_out);
    if (method_arg == NULL) {
      goto cleanup;
    }

    Dart_Handle payload_arg =
        g_state.api.Dart_NewTypedData(Dart_TypedData_kUint8, args_len);
    if (dllart_check_handle(payload_arg,
                            "Dart_NewTypedData(args)",
                            error_out) != 0) {
      goto cleanup;
    }

    if (args_len > 0) {
      Dart_Handle set_bytes = g_state.api.Dart_ListSetAsBytes(
          payload_arg, 0, args, (intptr_t)args_len);
      if (dllart_check_handle(set_bytes,
                              "Dart_ListSetAsBytes(args)",
                              error_out) != 0) {
        goto cleanup;
      }
    }

    Dart_Handle call_args[2] = {method_arg, payload_arg};
    Dart_Handle result =
        g_state.api.Dart_Invoke(root_library, dispatch_name, 2, call_args);
    if (dllart_check_handle_call(result, "Dart_Invoke(dllart_dispatch_bytes)",
                                 "bytes", method, -1, "bytes",
                                 error_out) != 0) {
      goto cleanup;
    }

    intptr_t result_len = 0;
    Dart_Handle length_status = g_state.api.Dart_ListLength(result, &result_len);
    if (dllart_check_handle_call(length_status, "Dart_ListLength(result)",
                                 "bytes", method, -1, "bytes",
                                 error_out) != 0) {
      goto cleanup;
    }
    if (result_len < 0 || result_len > INT32_MAX) {
      dllart_set_limit_exceeded(error_out, "Result bytes length is out of range");
      goto cleanup;
    }
    if ((size_t)result_len > (size_t)DLLART_BYTES_OUT_MAX_BYTES) {
      dllart_set_limit_exceeded(
          error_out, "result exceeds configured bytes_out_max_bytes");
      goto cleanup;
    }

    uint8_t* out = NULL;
    if (result_len > 0) {
      out = (uint8_t*)malloc((size_t)result_len);
      if (out == NULL) {
        dllart_set_error_code(
            error_out, DLLART_E_OOM, "Out of memory while copying result bytes");
        goto cleanup;
      }

      Dart_Handle get_bytes = g_state.api.Dart_ListGetAsBytes(
          result, 0, out, result_len);
      if (dllart_check_handle_call(get_bytes, "Dart_ListGetAsBytes(result)",
                                   "bytes", method, -1, "bytes",
                                   error_out) != 0) {
        free(out);
        goto cleanup;
      }
    } else {
      out = (uint8_t*)malloc(1);
      if (out == NULL) {
        dllart_set_error_code(
            error_out, DLLART_E_OOM, "Out of memory while allocating empty result");
        goto cleanup;
      }
    }

    if (result_out != NULL) {
      *result_out = out;
    } else {
      free(out);
    }
    if (result_len_out != NULL) {
      *result_len_out = (int32_t)result_len;
    }
  }

  status = 0;

cleanup:
  g_state.api.Dart_ExitScope();
  g_state.api.Dart_ExitIsolate();
  dllart_call_mutex_unlock(state);
  return status;
}

int dllart_call_bytes_index(int32_t method_id,
                            const uint8_t* args,
                            int32_t args_len,
                            uint8_t** result_out,
                            int32_t* result_len_out,
                            char** error_out) {
  int status = -1;

  if (result_out != NULL) {
    *result_out = NULL;
  }
  if (result_len_out != NULL) {
    *result_len_out = 0;
  }
  if (error_out != NULL) {
    *error_out = NULL;
  }
  dllart_clear_last_error();

  if (dllart_should_proxy_thread_call()) {
#if !defined(_WIN32)
    DllartCallBytesIndexContext call = {
        .method_id = method_id,
        .args = args,
        .args_len = args_len,
        .result_out = result_out,
        .result_len_out = result_len_out,
        .error_out = error_out,
    };
    return dllart_call_on_real_thread(
        dllart_call_bytes_index_thread_entry, &call, error_out);
#endif
  }

  if (method_id < 0) {
    return dllart_set_invalid_argument(error_out, "method_id cannot be negative");
  }
  if (args_len < 0) {
    return dllart_set_invalid_argument(error_out, "args_len cannot be negative");
  }
  if (args_len > 0 && args == NULL) {
    return dllart_set_invalid_argument(error_out, "args cannot be null when args_len > 0");
  }
  if ((size_t)args_len > (size_t)DLLART_BYTES_IN_MAX_BYTES) {
    return dllart_set_limit_exceeded(
        error_out, "args exceeds configured bytes_in_max_bytes");
  }

  DllartIsolateState* state = NULL;
  dllart_mutex_lock();
  if (dllart_pick_isolate_for_call(&state, error_out) != 0) {
    dllart_mutex_unlock();
    return -1;
  }
  dllart_call_mutex_lock(state);
  dllart_mutex_unlock();

  g_state.api.Dart_EnterIsolate(state->isolate);
  g_state.api.Dart_EnterScope();

  {
    Dart_Handle root_library =
        state->root_library_handle != NULL
            ? g_state.api.Dart_HandleFromPersistent(state->root_library_handle)
            : g_state.api.Dart_RootLibrary();
    if (dllart_check_handle(root_library, "Dart_RootLibrary", error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle dispatch_name =
        state->dispatch_bytes_index_handle != NULL
            ? g_state.api.Dart_HandleFromPersistent(
                  state->dispatch_bytes_index_handle)
            : g_state.api.Dart_NewStringFromCString(
                  "dllart_dispatch_bytes_index");
    if (dllart_check_handle(
            dispatch_name,
            "Dart_HandleFromPersistent(dllart_dispatch_bytes_index)",
            error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle method_id_arg = g_state.api.Dart_NewInteger(method_id);
    if (dllart_check_handle(method_id_arg,
                            "Dart_NewInteger(method_id)",
                            error_out) != 0) {
      goto cleanup;
    }

    Dart_Handle payload_arg =
        g_state.api.Dart_NewTypedData(Dart_TypedData_kUint8, args_len);
    if (dllart_check_handle(payload_arg,
                            "Dart_NewTypedData(args)",
                            error_out) != 0) {
      goto cleanup;
    }

    if (args_len > 0) {
      Dart_Handle set_bytes = g_state.api.Dart_ListSetAsBytes(
          payload_arg, 0, args, (intptr_t)args_len);
      if (dllart_check_handle(set_bytes,
                              "Dart_ListSetAsBytes(args)",
                              error_out) != 0) {
        goto cleanup;
      }
    }

    Dart_Handle call_args[2] = {method_id_arg, payload_arg};
    Dart_Handle result =
        g_state.api.Dart_Invoke(root_library, dispatch_name, 2, call_args);
    if (dllart_check_handle_call(result,
                                 "Dart_Invoke(dllart_dispatch_bytes_index)",
                                 "bytes_index", NULL, method_id, "bytes",
                                 error_out) != 0) {
      goto cleanup;
    }

    intptr_t result_len = 0;
    Dart_Handle length_status = g_state.api.Dart_ListLength(result, &result_len);
    if (dllart_check_handle_call(length_status, "Dart_ListLength(result)",
                                 "bytes_index", NULL, method_id, "bytes",
                                 error_out) != 0) {
      goto cleanup;
    }
    if (result_len < 0 || result_len > INT32_MAX) {
      dllart_set_limit_exceeded(error_out, "Result bytes length is out of range");
      goto cleanup;
    }
    if ((size_t)result_len > (size_t)DLLART_BYTES_OUT_MAX_BYTES) {
      dllart_set_limit_exceeded(
          error_out, "result exceeds configured bytes_out_max_bytes");
      goto cleanup;
    }

    uint8_t* out = NULL;
    if (result_len > 0) {
      out = (uint8_t*)malloc((size_t)result_len);
      if (out == NULL) {
        dllart_set_error_code(
            error_out, DLLART_E_OOM, "Out of memory while copying result bytes");
        goto cleanup;
      }

      Dart_Handle get_bytes = g_state.api.Dart_ListGetAsBytes(
          result, 0, out, result_len);
      if (dllart_check_handle_call(get_bytes, "Dart_ListGetAsBytes(result)",
                                   "bytes_index", NULL, method_id, "bytes",
                                   error_out) != 0) {
        free(out);
        goto cleanup;
      }
    } else {
      out = (uint8_t*)malloc(1);
      if (out == NULL) {
        dllart_set_error_code(
            error_out, DLLART_E_OOM, "Out of memory while allocating empty result");
        goto cleanup;
      }
    }

    if (result_out != NULL) {
      *result_out = out;
    } else {
      free(out);
    }
    if (result_len_out != NULL) {
      *result_len_out = (int32_t)result_len;
    }
  }

  status = 0;

cleanup:
  g_state.api.Dart_ExitScope();
  g_state.api.Dart_ExitIsolate();
  dllart_call_mutex_unlock(state);
  return status;
}

int dllart_call(const char* function_name,
                const char* args_json,
                char** result_json_out,
                char** error_out) {
  dllart_clear_last_error();
  return dllart_call_json(function_name, args_json, result_json_out, error_out);
}

int dllart_last_error_code(void) {
  return g_dllart_last_error_code;
}

int dllart_last_error_json(char** error_json_out) {
  if (error_json_out == NULL) {
    dllart_record_last_error(DLLART_E_INVALID_ARGUMENT,
                             "error_json_out cannot be null",
                             "dllart_last_error_json");
    return -1;
  }
  *error_json_out = NULL;

  const char* source = g_dllart_last_error_json;
  if (source == NULL || source[0] == '\0') {
    source =
        "{\"code\":0,\"code_name\":\"DLLART_E_OK\",\"message\":\"\",\"context\":\"\"}";
  }

  char* out = dllart_strdup(source);
  if (out == NULL) {
    dllart_record_last_error(DLLART_E_OOM,
                             "Out of memory while copying last error json",
                             "dllart_last_error_json");
    return -1;
  }
  *error_json_out = out;
  return 0;
}

void dllart_shutdown(void) {
  if (dllart_should_proxy_thread_call()) {
#if !defined(_WIN32)
    DllartShutdownContext call = {
        .unused = 0,
    };
    (void)dllart_call_on_real_thread(dllart_shutdown_thread_entry, &call, NULL);
    return;
#endif
  }

  dllart_mutex_lock();
  if (g_state.isolates != NULL && g_state.isolate_count > 0) {
    for (size_t i = 0; i < g_state.isolate_count; i++) {
      dllart_call_mutex_lock(&g_state.isolates[i]);
    }
    for (size_t i = 0; i < g_state.isolate_count; i++) {
      dllart_reset_isolate_state(&g_state.isolates[i]);
      dllart_call_mutex_unlock(&g_state.isolates[i]);
      dllart_call_mutex_destroy(&g_state.isolates[i]);
    }
    free(g_state.isolates);
    g_state.isolates = NULL;
    g_state.isolate_count = 0;
    g_state.next_isolate_index = 0;
  }
  dllart_mutex_unlock();
}

void dllart_string_free(char* value) {
  free(value);
}

void dllart_bytes_free(uint8_t* value) {
  free(value);
}
