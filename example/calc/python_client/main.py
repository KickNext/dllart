import ctypes
import os
import sys

if len(sys.argv) != 2:
    print(f"Usage: {sys.argv[0]} <path-to-lib>")
    sys.exit(1)

lib_path = os.path.abspath(sys.argv[1])
lib = ctypes.CDLL(lib_path)
prefix = "calc_dllart"

c_char_p_p = ctypes.POINTER(ctypes.c_char_p)

init_fn = getattr(lib, f"{prefix}_init")
init_fn.argtypes = [ctypes.c_char_p, c_char_p_p]
init_fn.restype = ctypes.c_int

call_json_fn = getattr(lib, f"{prefix}_call_json")
call_json_fn.argtypes = [ctypes.c_char_p, ctypes.c_char_p, c_char_p_p, c_char_p_p]
call_json_fn.restype = ctypes.c_int

call_i64_4_fn = getattr(lib, f"{prefix}_call_i64_4")
call_i64_4_fn.argtypes = [
    ctypes.c_char_p,
    ctypes.c_longlong,
    ctypes.c_longlong,
    ctypes.c_longlong,
    ctypes.c_longlong,
    ctypes.POINTER(ctypes.c_longlong),
    c_char_p_p,
]
call_i64_4_fn.restype = ctypes.c_int

call_f64_2_fn = getattr(lib, f"{prefix}_call_f64_2")
call_f64_2_fn.argtypes = [
    ctypes.c_char_p,
    ctypes.c_double,
    ctypes.c_double,
    ctypes.POINTER(ctypes.c_double),
    c_char_p_p,
]
call_f64_2_fn.restype = ctypes.c_int

shutdown_fn = getattr(lib, f"{prefix}_shutdown")
shutdown_fn.argtypes = []
shutdown_fn.restype = None

string_free_fn = getattr(lib, f"{prefix}_string_free")
string_free_fn.argtypes = [ctypes.c_char_p]
string_free_fn.restype = None

error = ctypes.c_char_p()
rc = init_fn(None, ctypes.byref(error))
if rc != 0:
    message = error.value.decode("utf-8") if error.value else "<unknown>"
    print(f"{prefix}_init failed: {message}", file=sys.stderr)
    if error.value:
        string_free_fn(error)
    sys.exit(1)

result = ctypes.c_char_p()
rc = call_json_fn(
    b"mul",
    b'{"a": 6, "b": 7}',
    ctypes.byref(result),
    ctypes.byref(error),
)
if rc != 0:
    message = error.value.decode("utf-8") if error.value else "<unknown>"
    print(f"{prefix}_call_json failed: {message}", file=sys.stderr)
    if error.value:
        string_free_fn(error)
    shutdown_fn()
    sys.exit(1)

print("Python result:", result.value.decode("utf-8"))
string_free_fn(result)

typed_i64_4 = ctypes.c_longlong()
rc = call_i64_4_fn(
    b"sum4_fast",
    1,
    2,
    3,
    4,
    ctypes.byref(typed_i64_4),
    ctypes.byref(error),
)
if rc != 0:
    message = error.value.decode("utf-8") if error.value else "<unknown>"
    print(f"{prefix}_call_i64_4 failed: {message}", file=sys.stderr)
    if error.value:
        string_free_fn(error)
    shutdown_fn()
    sys.exit(1)
print("Python i64_4 result:", typed_i64_4.value)

typed_f64_2 = ctypes.c_double()
rc = call_f64_2_fn(
    b"avg2_fast",
    10.0,
    14.0,
    ctypes.byref(typed_f64_2),
    ctypes.byref(error),
)
if rc != 0:
    message = error.value.decode("utf-8") if error.value else "<unknown>"
    print(f"{prefix}_call_f64_2 failed: {message}", file=sys.stderr)
    if error.value:
        string_free_fn(error)
    shutdown_fn()
    sys.exit(1)
print("Python f64_2 result:", typed_f64_2.value)

shutdown_fn()
