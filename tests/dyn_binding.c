#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static int64_t gene_dyn_last_value = 0;

int64_t gene_dyn_add(int64_t a, int64_t b) {
  return a + b;
}

bool gene_dyn_is_even(int64_t n) {
  return (n % 2) == 0;
}

int64_t gene_dyn_bool_high_bits(void) {
  return 0x100;
}

int64_t gene_dyn_strlen(const char *s) {
  if (s == NULL) {
    return -1;
  }
  return (int64_t)strlen(s);
}

const char *gene_dyn_greet(const char *name) {
  static char buffer[128];
  snprintf(buffer, sizeof(buffer), "hello, %s", name == NULL ? "nil" : name);
  return buffer;
}

void gene_dyn_set_last(int64_t value) {
  gene_dyn_last_value = value;
}

int64_t gene_dyn_get_last(void) {
  return gene_dyn_last_value;
}

void *gene_dyn_static_ptr(void) {
  return &gene_dyn_last_value;
}

void *gene_dyn_identity_ptr(void *p) {
  return p;
}
