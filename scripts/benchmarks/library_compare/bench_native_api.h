#ifndef BENCH_NATIVE_API_H
#define BENCH_NATIVE_API_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

int bench_init(const char* runtime_path, char** error_out);
int bench_cpu_work(int64_t iterations,
                   int64_t seed,
                   int64_t* checksum_out,
                   char** error_out);
int bench_io_write(const char* path,
                   int64_t file_mb,
                   int64_t* bytes_written_out,
                   char** error_out);
int bench_io_read(const char* path,
                  int64_t file_mb,
                  int64_t* checksum_out,
                  char** error_out);
void bench_shutdown(void);
void bench_string_free(char* value);

#ifdef __cplusplus
}
#endif

#endif
