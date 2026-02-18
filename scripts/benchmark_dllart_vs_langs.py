#!/usr/bin/env python3
import argparse
import ctypes
import json
import os
import platform
import statistics
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Tuple


class BenchError(RuntimeError):
    pass


def run_cmd(cmd: List[str]) -> str:
    completed = subprocess.run(cmd, check=True, capture_output=True, text=True)
    return completed.stdout.strip()


class NativeLib:
    def __init__(self, path: str):
        self.path = path
        self.lib = ctypes.CDLL(path)

        self.lib.bench_init.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p)]
        self.lib.bench_init.restype = ctypes.c_int

        self.lib.bench_cpu_work.argtypes = [
            ctypes.c_int64,
            ctypes.c_int64,
            ctypes.POINTER(ctypes.c_int64),
            ctypes.POINTER(ctypes.c_void_p),
        ]
        self.lib.bench_cpu_work.restype = ctypes.c_int

        self.lib.bench_io_write.argtypes = [
            ctypes.c_char_p,
            ctypes.c_int64,
            ctypes.POINTER(ctypes.c_int64),
            ctypes.POINTER(ctypes.c_void_p),
        ]
        self.lib.bench_io_write.restype = ctypes.c_int

        self.lib.bench_io_read.argtypes = [
            ctypes.c_char_p,
            ctypes.c_int64,
            ctypes.POINTER(ctypes.c_int64),
            ctypes.POINTER(ctypes.c_void_p),
        ]
        self.lib.bench_io_read.restype = ctypes.c_int

        self.lib.bench_shutdown.argtypes = []
        self.lib.bench_shutdown.restype = None

        self.lib.bench_string_free.argtypes = [ctypes.c_void_p]
        self.lib.bench_string_free.restype = None

    def _take_error(self, err_ptr: ctypes.c_void_p) -> str:
        if not err_ptr.value:
            return "<unknown error>"
        message = ctypes.string_at(err_ptr.value).decode("utf-8", errors="replace")
        self.lib.bench_string_free(err_ptr)
        return message

    def _raise_if_failed(self, rc: int, err_ptr: ctypes.c_void_p, context: str) -> None:
        if rc == 0:
            return
        raise BenchError(f"{context} failed: {self._take_error(err_ptr)}")

    def init(self) -> None:
        err = ctypes.c_void_p()
        rc = self.lib.bench_init(None, ctypes.byref(err))
        self._raise_if_failed(rc, err, "bench_init")

    def cpu_work(self, iterations: int, seed: int) -> int:
        err = ctypes.c_void_p()
        out = ctypes.c_int64()
        rc = self.lib.bench_cpu_work(iterations, seed, ctypes.byref(out), ctypes.byref(err))
        self._raise_if_failed(rc, err, "bench_cpu_work")
        return int(out.value)

    def io_write(self, path: str, file_mb: int) -> int:
        err = ctypes.c_void_p()
        out = ctypes.c_int64()
        rc = self.lib.bench_io_write(path.encode("utf-8"), file_mb, ctypes.byref(out), ctypes.byref(err))
        self._raise_if_failed(rc, err, "bench_io_write")
        return int(out.value)

    def io_read(self, path: str, file_mb: int) -> int:
        err = ctypes.c_void_p()
        out = ctypes.c_int64()
        rc = self.lib.bench_io_read(path.encode("utf-8"), file_mb, ctypes.byref(out), ctypes.byref(err))
        self._raise_if_failed(rc, err, "bench_io_read")
        return int(out.value)

    def shutdown(self) -> None:
        self.lib.bench_shutdown()


class DllartLib:
    def __init__(self, path: str):
        self.path = path
        self.lib = ctypes.CDLL(path)

        self.lib.calc_dllart_init.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_void_p)]
        self.lib.calc_dllart_init.restype = ctypes.c_int

        self.lib.calc_dllart_call_i64_2.argtypes = [
            ctypes.c_char_p,
            ctypes.c_int64,
            ctypes.c_int64,
            ctypes.POINTER(ctypes.c_int64),
            ctypes.POINTER(ctypes.c_void_p),
        ]
        self.lib.calc_dllart_call_i64_2.restype = ctypes.c_int

        self.lib.calc_dllart_call_json.argtypes = [
            ctypes.c_char_p,
            ctypes.c_char_p,
            ctypes.POINTER(ctypes.c_void_p),
            ctypes.POINTER(ctypes.c_void_p),
        ]
        self.lib.calc_dllart_call_json.restype = ctypes.c_int

        self.lib.calc_dllart_shutdown.argtypes = []
        self.lib.calc_dllart_shutdown.restype = None

        self.lib.calc_dllart_string_free.argtypes = [ctypes.c_void_p]
        self.lib.calc_dllart_string_free.restype = None

    def _take_string(self, ptr: ctypes.c_void_p) -> str:
        if not ptr.value:
            return ""
        value = ctypes.string_at(ptr.value).decode("utf-8", errors="replace")
        self.lib.calc_dllart_string_free(ptr)
        return value

    def _raise_if_failed(self, rc: int, err_ptr: ctypes.c_void_p, context: str) -> None:
        if rc == 0:
            return
        raise BenchError(f"{context} failed: {self._take_string(err_ptr)}")

    def init(self) -> None:
        err = ctypes.c_void_p()
        rc = self.lib.calc_dllart_init(None, ctypes.byref(err))
        self._raise_if_failed(rc, err, "calc_dllart_init")

    def cpu_work(self, iterations: int, seed: int) -> int:
        err = ctypes.c_void_p()
        out = ctypes.c_int64()
        rc = self.lib.calc_dllart_call_i64_2(
            b"cpu_work_fast",
            iterations,
            seed,
            ctypes.byref(out),
            ctypes.byref(err),
        )
        self._raise_if_failed(rc, err, "calc_dllart_call_i64_2(cpu_work_fast)")
        return int(out.value)

    def _call_json_int(self, method: str, payload: Dict[str, object]) -> int:
        result = ctypes.c_void_p()
        err = ctypes.c_void_p()
        payload_json = json.dumps(payload, separators=(",", ":")).encode("utf-8")
        rc = self.lib.calc_dllart_call_json(
            method.encode("utf-8"),
            payload_json,
            ctypes.byref(result),
            ctypes.byref(err),
        )
        self._raise_if_failed(rc, err, f"calc_dllart_call_json({method})")
        raw = self._take_string(result)
        try:
            parsed = json.loads(raw)
        except json.JSONDecodeError as exc:
            raise BenchError(f"{method} returned invalid JSON: {raw}") from exc
        if isinstance(parsed, int):
            return parsed
        if isinstance(parsed, dict):
            if parsed.get("ok") is True and isinstance(parsed.get("result"), int):
                return int(parsed["result"])
            if isinstance(parsed.get("result"), int):
                return int(parsed["result"])
        raise BenchError(f"{method} returned non-int payload: {raw}")

    def io_write(self, path: str, file_mb: int) -> int:
        return self._call_json_int("io_write", {"path": path, "fileMb": file_mb})

    def io_read(self, path: str, file_mb: int) -> int:
        return self._call_json_int("io_read", {"path": path, "fileMb": file_mb})

    def shutdown(self) -> None:
        self.lib.calc_dllart_shutdown()


@dataclass
class RunMetrics:
    cpu_ns_per_op: float
    cpu_mops: float
    io_write_mb_s: float
    io_read_mb_s: float
    checksum: int


@dataclass
class Summary:
    cpu_ns_per_op_avg: float
    cpu_ns_per_op_min: float
    cpu_ns_per_op_max: float
    cpu_mops_avg: float
    io_write_mb_s_avg: float
    io_read_mb_s_avg: float
    checksum: str


def summarize(metrics: List[RunMetrics]) -> Summary:
    cpu_ns = [m.cpu_ns_per_op for m in metrics]
    cpu_mops = [m.cpu_mops for m in metrics]
    write_s = [m.io_write_mb_s for m in metrics]
    read_s = [m.io_read_mb_s for m in metrics]
    checksums = {m.checksum for m in metrics}
    checksum_value = str(next(iter(checksums))) if len(checksums) == 1 else "mixed"
    return Summary(
        cpu_ns_per_op_avg=statistics.mean(cpu_ns),
        cpu_ns_per_op_min=min(cpu_ns),
        cpu_ns_per_op_max=max(cpu_ns),
        cpu_mops_avg=statistics.mean(cpu_mops),
        io_write_mb_s_avg=statistics.mean(write_s),
        io_read_mb_s_avg=statistics.mean(read_s),
        checksum=checksum_value,
    )


def run_target(name: str, lib_obj, iterations: int, file_mb: int, repeats: int, tmp_dir: Path, seed: int) -> Tuple[Summary, List[RunMetrics]]:
    runs: List[RunMetrics] = []
    for run_idx in range(1, repeats + 1):
        lib_obj.init()

        cpu_t0 = time.perf_counter_ns()
        cpu_checksum = lib_obj.cpu_work(iterations, seed)
        cpu_t1 = time.perf_counter_ns()

        payload_path = tmp_dir / f"{name}_payload_{run_idx}.bin"

        write_t0 = time.perf_counter_ns()
        bytes_written = lib_obj.io_write(str(payload_path), file_mb)
        write_t1 = time.perf_counter_ns()

        read_t0 = time.perf_counter_ns()
        io_checksum = lib_obj.io_read(str(payload_path), file_mb)
        read_t1 = time.perf_counter_ns()

        lib_obj.shutdown()

        cpu_seconds = (cpu_t1 - cpu_t0) / 1e9
        write_seconds = (write_t1 - write_t0) / 1e9
        read_seconds = (read_t1 - read_t0) / 1e9

        if cpu_seconds <= 0 or write_seconds <= 0 or read_seconds <= 0:
            raise BenchError("timer produced non-positive duration")

        cpu_ns_per_op = (cpu_t1 - cpu_t0) / iterations
        cpu_mops = iterations / cpu_seconds / 1e6
        write_mb_s = (bytes_written / (1024.0 * 1024.0)) / write_seconds
        read_mb_s = file_mb / read_seconds
        checksum = cpu_checksum ^ io_checksum

        metric = RunMetrics(
            cpu_ns_per_op=cpu_ns_per_op,
            cpu_mops=cpu_mops,
            io_write_mb_s=write_mb_s,
            io_read_mb_s=read_mb_s,
            checksum=checksum,
        )
        runs.append(metric)

        print(
            f"{name} run {run_idx}/{repeats}: "
            f"cpu_ns_per_op={cpu_ns_per_op:.4f} "
            f"cpu_mops={cpu_mops:.2f} "
            f"io_write_mb_s={write_mb_s:.2f} "
            f"io_read_mb_s={read_mb_s:.2f} "
            f"checksum={checksum}"
        )

    return summarize(runs), runs


def toolchain_versions(cxx: str, rustc: str, go: str, python_exec: str) -> Dict[str, str]:
    return {
        "cxx": run_cmd([cxx, "--version"]).splitlines()[0],
        "rust": run_cmd([rustc, "--version"]),
        "go": run_cmd([go, "version"]),
        "python": run_cmd([python_exec, "--version"]),
    }


def platform_info() -> Dict[str, str]:
    cpu_label = platform.processor() or platform.machine()
    os_label = platform.platform()
    info = {
        "platform": f"{platform.system()} {platform.release()} {platform.machine()}",
        "os": os_label,
        "cpu": cpu_label,
    }
    if platform.system() == "Darwin":
        try:
            cpu_model = run_cmd(["sysctl", "-n", "machdep.cpu.brand_string"])
            if cpu_model:
                info["cpu"] = cpu_model
        except Exception:
            pass
        try:
            sw = run_cmd(["sw_vers"]).splitlines()
            if sw:
                info["os"] = "; ".join(line.strip() for line in sw if line.strip())
        except Exception:
            pass
        try:
            mem_bytes = int(run_cmd(["sysctl", "-n", "hw.memsize"]))
            info["ram"] = f"{mem_bytes / (1024**3):.2f} GiB"
        except Exception:
            info["ram"] = "unknown"
    else:
        info["ram"] = "unknown"
    return info


def write_report(
    report_path: Path,
    run_utc: str,
    platform_meta: Dict[str, str],
    versions: Dict[str, str],
    iterations: int,
    file_mb: int,
    repeats: int,
    summaries: Dict[str, Summary],
) -> None:
    def row(label: str, summary: Summary) -> str:
        return (
            f"| {label} | {summary.cpu_ns_per_op_avg:.4f} | {summary.cpu_ns_per_op_min:.4f} "
            f"| {summary.cpu_ns_per_op_max:.4f} | {summary.cpu_mops_avg:.2f} "
            f"| {summary.io_write_mb_s_avg:.2f} | {summary.io_read_mb_s_avg:.2f} "
            f"| {summary.checksum} |"
        )

    report = f"""# DLLART vs C++/Rust/Go (same logic, Python harness)

- Run at (UTC): {run_utc}
- Platform: {platform_meta['platform']}
- OS: {platform_meta['os']}
- CPU: {platform_meta['cpu']}
- RAM: {platform_meta['ram']}
- Iterations per run: {iterations}
- File size per run: {file_mb} MiB
- Repeats per target: {repeats}

## Toolchains

- C++: {versions['cxx']}
- Rust: {versions['rust']}
- Go: {versions['go']}
- Python: {versions['python']}

## Identical Logic

- CPU: same integer loop (`x = (x*1103515245 + 12345) & 0x7fffffff`, checksum accumulate).
- I/O write: same deterministic 1 MiB xorshift buffer pattern into in-memory payload.
- I/O read: same checksum over in-memory payload bytes.

## Results (average with min/max)

| Target | CPU ns/op avg | CPU ns/op min | CPU ns/op max | CPU Mops/s avg | Write MB/s avg | Read MB/s avg | Checksum |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
{row('dllart', summaries['dllart'])}
{row('C++ native', summaries['cpp'])}
{row('Rust native', summaries['rust'])}
{row('Go native', summaries['go'])}

## Notes

- Measurements are driven by one Python (`ctypes`) harness for equal calling conditions.
- `dllart` target uses generated `/example/calc/build/calc/lib/libcalc` and methods `cpu_work_fast`, `io_write`, `io_read`.
- I/O metric here is in-memory throughput (input/output payload), not disk throughput.
"""
    report_path.write_text(report, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Benchmark dllart vs native C++/Rust/Go libraries")
    parser.add_argument("--dllart-lib", required=True)
    parser.add_argument("--cpp-lib", required=True)
    parser.add_argument("--rust-lib", required=True)
    parser.add_argument("--go-lib", required=True)
    parser.add_argument("--report", required=True)
    parser.add_argument("--iterations", type=int, default=100_000_000)
    parser.add_argument("--file-mb", type=int, default=256)
    parser.add_argument("--repeats", type=int, default=3)
    parser.add_argument("--tmp-dir", required=True)
    parser.add_argument("--seed", type=int, default=123456789)
    parser.add_argument("--cxx", default="c++")
    parser.add_argument("--rustc", default="rustc")
    parser.add_argument("--go", default="go")
    parser.add_argument("--python", default=sys.executable)
    args = parser.parse_args()

    if args.iterations <= 0 or args.file_mb <= 0 or args.repeats <= 0:
        raise BenchError("iterations, file-mb, repeats must be > 0")

    tmp_dir = Path(args.tmp_dir)
    tmp_dir.mkdir(parents=True, exist_ok=True)

    targets = {
        "dllart": DllartLib(args.dllart_lib),
        "cpp": NativeLib(args.cpp_lib),
        "rust": NativeLib(args.rust_lib),
        "go": NativeLib(args.go_lib),
    }

    summaries: Dict[str, Summary] = {}
    for key in ["dllart", "cpp", "rust", "go"]:
        summary, _runs = run_target(
            key,
            targets[key],
            args.iterations,
            args.file_mb,
            args.repeats,
            tmp_dir,
            args.seed,
        )
        summaries[key] = summary

    versions = toolchain_versions(args.cxx, args.rustc, args.go, args.python)
    platform_meta = platform_info()
    run_utc = time.strftime("%Y-%m-%d %H:%M:%S UTC", time.gmtime())

    report_path = Path(args.report)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    write_report(
        report_path,
        run_utc,
        platform_meta,
        versions,
        args.iterations,
        args.file_mb,
        args.repeats,
        summaries,
    )

    print(f"Report written to: {report_path}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except BenchError as exc:
        print(f"benchmark failed: {exc}", file=sys.stderr)
        raise SystemExit(1)
