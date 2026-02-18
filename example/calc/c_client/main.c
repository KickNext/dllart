#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "calc_api.h"

static int fail(const char* where, char* error) {
  fprintf(stderr, "%s failed: %s\n", where, error ? error : "<unknown>");
  if (error != NULL) {
    calc_string_free(error);
  }
  return 1;
}

int main(void) {
  char* error = NULL;
  if (calc_init(NULL, &error) != 0) {
    return fail("calc_init", error);
  }

  char* json_result = NULL;
  if (calc_add("{\"a\": 20, \"b\": 22}", &json_result, &error) != 0) {
    calc_shutdown();
    return fail("calc_add", error);
  }
  printf("C json result: %s\n", json_result);
  calc_string_free(json_result);

  int64_t sum4 = 0;
  if (calc_sum4_fast_i64_4_fast(1, 2, 3, 4, &sum4, &error) != 0) {
    calc_shutdown();
    return fail("calc_sum4_fast_i64_4_fast", error);
  }
  printf("C i64_4 result: %lld\n", (long long)sum4);

  double avg2 = 0.0;
  if (calc_avg2_fast_f64_2_fast(10.0, 14.0, &avg2, &error) != 0) {
    calc_shutdown();
    return fail("calc_avg2_fast_f64_2_fast", error);
  }
  printf("C f64_2 result: %.1f\n", avg2);

  calc_shutdown();
  return 0;
}
