# DLLART vs C++/Rust/Go (same logic, Python harness)

- Run at (UTC): 2026-02-18 20:07:51 UTC
- Platform: Darwin 25.3.0 arm64
- OS: ProductName:		macOS; ProductVersion:		26.3; BuildVersion:		25D125
- CPU: Apple M4
- RAM: 16.00 GiB
- Iterations per run: 100000000
- File size per run: 256 MiB
- Repeats per target: 3

## Toolchains

- C++: Apple clang version 17.0.0 (clang-1700.6.3.2)
- Rust: rustc 1.92.0 (ded5c06cf 2025-12-08) (Homebrew)
- Go: go version go1.26.0 darwin/arm64
- Python: Python 3.9.6

## Identical Logic

- CPU: same integer loop (`x = (x*1103515245 + 12345) & 0x7fffffff`, checksum accumulate).
- I/O write: same deterministic 1 MiB xorshift buffer pattern into in-memory payload.
- I/O read: same checksum over in-memory payload bytes.

## Results (average with min/max)

| Target | CPU ns/op avg | CPU ns/op min | CPU ns/op max | CPU Mops/s avg | Write MB/s avg | Read MB/s avg | Checksum |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| dllart | 1.7469 | 1.6457 | 1.9175 | 575.11 | 14836.97 | 3019.25 | 33562080000 |
| C++ native | 0.9386 | 0.9314 | 0.9478 | 1065.49 | 26201.43 | 22239.56 | 33562080000 |
| Rust native | 0.9383 | 0.9360 | 0.9413 | 1065.75 | 30717.03 | 22003.55 | 33562080000 |
| Go native | 1.1673 | 1.1640 | 1.1691 | 856.67 | 8607.58 | 3688.86 | 33562080000 |

## Notes

- Measurements are driven by one Python (`ctypes`) harness for equal calling conditions.
- `dllart` target uses generated `/example/calc/build/calc/lib/libcalc` and methods `cpu_work_fast`, `io_write`, `io_read`.
- I/O metric here is in-memory throughput (input/output payload), not disk throughput.
