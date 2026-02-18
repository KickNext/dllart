#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

#include "calc_api.h"

static uint64_t now_ns(void) {
  struct timespec ts;
  clock_gettime(CLOCK_MONOTONIC, &ts);
  return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}

static void fail_with_error(const char* ctx, char* err) {
  fprintf(stderr, "%s failed: %s\n", ctx, err ? err : "<unknown>");
  if (err != NULL) {
    calc_string_free(err);
  }
  exit(1);
}

static void bench_json_add(int iterations) {
  const char* payload = "{\"a\":123,\"b\":456}";
  char* err = NULL;
  char* result = NULL;

  const uint64_t t0 = now_ns();
  for (int i = 0; i < iterations; i++) {
    const int rc = calc_add(payload, &result, &err);
    if (rc != 0) {
      fail_with_error("calc_add(json)", err);
    }
    calc_string_free(result);
    result = NULL;
  }
  const uint64_t t1 = now_ns();

  const double elapsed_ns = (double)(t1 - t0);
  const double avg_us = elapsed_ns / (double)iterations / 1000.0;
  const double throughput = (double)iterations * 1e9 / elapsed_ns;

  printf("json_add:  iterations=%d avg=%.3fus throughput=%.0f calls/s\n",
         iterations,
         avg_us,
         throughput);
}

static void bench_typed_add_i64_2_fallback(int iterations) {
  char* err = NULL;
  int64_t result = 0;

  const uint64_t t0 = now_ns();
  for (int i = 0; i < iterations; i++) {
    const int rc = calc_add_i64_2(123, 456, &result, &err);
    if (rc != 0) {
      fail_with_error("calc_add_i64_2(typed_fallback)", err);
    }
    if (result != 579) {
      fprintf(stderr, "calc_add_i64_2 produced unexpected result: %lld\n",
              (long long)result);
      exit(1);
    }
  }
  const uint64_t t1 = now_ns();

  const double elapsed_ns = (double)(t1 - t0);
  const double avg_us = elapsed_ns / (double)iterations / 1000.0;
  const double throughput = (double)iterations * 1e9 / elapsed_ns;

  printf("typed_fallback_add: iterations=%d avg=%.3fus throughput=%.0f calls/s\n",
         iterations,
         avg_us,
         throughput);
}

static void bench_typed_add_fast_i64_2_direct(int iterations) {
  char* err = NULL;
  int64_t result = 0;

  const uint64_t t0 = now_ns();
  for (int i = 0; i < iterations; i++) {
    const int rc = calc_add_fast_i64_2_fast(123, 456, &result, &err);
    if (rc != 0) {
      fail_with_error("calc_add_fast_i64_2_fast(typed_direct)", err);
    }
    if (result != 579) {
      fprintf(stderr, "calc_add_fast_i64_2 produced unexpected result: %lld\n",
              (long long)result);
      exit(1);
    }
  }
  const uint64_t t1 = now_ns();

  const double elapsed_ns = (double)(t1 - t0);
  const double avg_us = elapsed_ns / (double)iterations / 1000.0;
  const double throughput = (double)iterations * 1e9 / elapsed_ns;

  printf("typed_direct_add: iterations=%d avg=%.3fus throughput=%.0f calls/s\n",
         iterations,
         avg_us,
         throughput);
}

int main(int argc, char** argv) {
  int iterations = 500000;
  if (argc >= 2) {
    iterations = atoi(argv[1]);
  }
  if (iterations <= 0) {
    fprintf(stderr, "iterations must be > 0\n");
    return 1;
  }

  char* err = NULL;
  if (calc_init(NULL, &err) != 0) {
    fail_with_error("calc_init", err);
  }

  bench_json_add(iterations);
  bench_typed_add_i64_2_fallback(iterations);
  bench_typed_add_fast_i64_2_direct(iterations);

  calc_shutdown();
  return 0;
}
