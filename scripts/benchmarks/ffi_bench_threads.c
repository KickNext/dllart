#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#include "calc_api.h"

typedef enum {
  MODE_JSON = 0,
  MODE_TYPED_FALLBACK = 1,
  MODE_TYPED_DIRECT = 2,
} BenchMode;

typedef struct {
  BenchMode mode;
  int iterations;
} WorkerArgs;

static uint64_t now_ns(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

static void fail(const char* ctx, char* err) {
  fprintf(stderr, "%s failed: %s\n", ctx, err ? err : "<unknown>");
  if (err != NULL) {
    calc_string_free(err);
  }
  exit(1);
}

static void* run_worker(void* raw) {
  WorkerArgs* args = (WorkerArgs*)raw;
  char* err = NULL;

  if (args->mode == MODE_JSON) {
    char* out = NULL;
    for (int i = 0; i < args->iterations; i++) {
      const int rc = calc_add("{\"a\":7,\"b\":35}", &out, &err);
      if (rc != 0) {
        fail("calc_add(json)", err);
      }
      calc_string_free(out);
      out = NULL;
    }
  } else if (args->mode == MODE_TYPED_FALLBACK) {
    int64_t out = 0;
    for (int i = 0; i < args->iterations; i++) {
      const int rc = calc_add_i64_2(7, 35, &out, &err);
      if (rc != 0) {
        fail("calc_add_i64_2(typed_fallback)", err);
      }
      if (out != 42) {
        fprintf(stderr, "typed result mismatch: %lld\n", (long long)out);
        exit(1);
      }
    }
  } else {
    int64_t out = 0;
    for (int i = 0; i < args->iterations; i++) {
      const int rc = calc_add_fast_i64_2_fast(7, 35, &out, &err);
      if (rc != 0) {
        fail("calc_add_fast_i64_2_fast(typed_direct)", err);
      }
      if (out != 42) {
        fprintf(stderr, "typed direct result mismatch: %lld\n", (long long)out);
        exit(1);
      }
    }
  }

  return NULL;
}

static void run_case(BenchMode mode,
                     const char* name,
                     int threads,
                     int iterations_per_thread) {
  pthread_t* ids = (pthread_t*)malloc(sizeof(pthread_t) * (size_t)threads);
  WorkerArgs* args = (WorkerArgs*)malloc(sizeof(WorkerArgs) * (size_t)threads);
  if (ids == NULL || args == NULL) {
    fprintf(stderr, "out of memory\n");
    exit(1);
  }

  const uint64_t t0 = now_ns();
  for (int i = 0; i < threads; i++) {
    args[i].mode = mode;
    args[i].iterations = iterations_per_thread;
    pthread_create(&ids[i], NULL, run_worker, &args[i]);
  }
  for (int i = 0; i < threads; i++) {
    pthread_join(ids[i], NULL);
  }
  const uint64_t t1 = now_ns();

  const int total = threads * iterations_per_thread;
  const double elapsed_ns = (double)(t1 - t0);
  const double avg_us = elapsed_ns / (double)total / 1000.0;
  const double throughput = (double)total * 1e9 / elapsed_ns;

  printf("%s: threads=%d total=%d avg=%.3fus throughput=%.0f calls/s\n",
         name,
         threads,
         total,
         avg_us,
         throughput);

  free(args);
  free(ids);
}

int main(int argc, char** argv) {
  int threads = 8;
  int per_thread = 100000;

  if (argc >= 2) {
    threads = atoi(argv[1]);
  }
  if (argc >= 3) {
    per_thread = atoi(argv[2]);
  }
  if (threads <= 0 || per_thread <= 0) {
    fprintf(stderr, "usage: ffi_bench_threads [threads>0] [iterations_per_thread>0]\n");
    return 1;
  }

  char* err = NULL;
  if (calc_init(NULL, &err) != 0) {
    fail("calc_init", err);
  }

  run_case(MODE_JSON, "json_add", threads, per_thread);
  run_case(MODE_TYPED_FALLBACK, "typed_fallback_add", threads, per_thread);
  run_case(MODE_TYPED_DIRECT, "typed_direct_add", threads, per_thread);

  calc_shutdown();
  return 0;
}
