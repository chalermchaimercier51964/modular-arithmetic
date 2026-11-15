#!/usr/bin/env bash
# Tests for modular_arithmetic.sh. Run with `bash test_modular_arithmetic.sh`.
# The script sources the library and calls its functions directly.

set -euo pipefail

# shellcheck source=modular_arithmetic.sh
source "$(dirname "$0")/modular_arithmetic.sh"

pass=0
fail=0

# assert_eq expected actual label
# Prints a TAP-like line and bumps the counters. Exits non-zero at the end if
# any assertion failed.
assert_eq() {
  local expected=$1 actual=$2 label=$3
  if [[ $expected == "$actual" ]]; then
    printf 'ok %d - %s\n' "$((pass + fail + 1))" "$label"
    pass=$((pass + 1))
  else
    printf 'not ok %d - %s\n' "$((pass + fail + 1))" "$label"
    printf '#   expected: %s\n#   actual:   %s\n' "$expected" "$actual"
    fail=$((fail + 1))
  fi
}

# assert_fails label cmd...
# Runs the command, expects a non-zero exit status, and checks that the status
# is 1 (our documented failure code).
assert_fails() {
  local label=$1; shift
  local status=0
  "$@" >/dev/null 2>&1 || status=$?
  if [[ $status -eq 1 ]]; then
    printf 'ok %d - %s\n' "$((pass + fail + 1))" "$label"
    pass=$((pass + 1))
  else
    printf 'not ok %d - %s\n' "$((pass + fail + 1))" "$label"
    printf '#   expected exit 1, got %s\n' "$status"
    fail=$((fail + 1))
  fi
}

# --- ma_mod ---------------------------------------------------------------
assert_eq 3 "$(ma_mod 10 7)" "ma_mod basic"
assert_eq 0 "$(ma_mod 0 7)" "ma_mod zero dividend"
assert_eq 0 "$(ma_mod 7 7)" "ma_mod exact multiple"
assert_eq 0 "$(ma_mod 5 1)" "ma_mod modulus one"
assert_fails "ma_mod rejects zero modulus" ma_mod 5 0
assert_fails "ma_mod rejects negative dividend string" ma_mod -1 7
assert_fails "ma_mod rejects non-numeric" ma_mod abc 7

# --- ma_add ---------------------------------------------------------------
assert_eq 1 "$(ma_add 3 5 7)" "ma_add no wrap"
assert_eq 2 "$(ma_add 6 6 10)" "ma_add wraps"
assert_eq 0 "$(ma_add 0 0 5)" "ma_add zeros"
assert_fails "ma_add rejects zero modulus" ma_add 1 2 0

# --- ma_mul ---------------------------------------------------------------
assert_eq 6 "$(ma_mul 2 3 7)" "ma_mul small"
assert_eq 0 "$(ma_mul 0 5 7)" "ma_mul zero"
assert_eq 1 "$(ma_mul 3 5 7)" "ma_mul wraps"
# 2^40 * 2^40 mod (2^40 + 1) == 1, a classic check that does not overflow.
assert_eq 1 "$(ma_mul 1099511627776 1099511627776 1099511627777)" "ma_mul large operands"
assert_fails "ma_mul rejects oversized modulus" ma_mul 1 1 4611686018427387905

# --- ma_pow ---------------------------------------------------------------
assert_eq 1 "$(ma_pow 2 0 7)" "ma_pow exponent zero"
assert_eq 2 "$(ma_pow 2 1 7)" "ma_pow exponent one"
assert_eq 4 "$(ma_pow 2 10 5)" "ma_pow wraps"
# Fermat: 2^(p-1) == 1 mod p for prime p.
assert_eq 1 "$(ma_pow 2 12 13)" "ma_pow Fermat little theorem"
assert_eq 0 "$(ma_pow 0 5 7)" "ma_pow zero base"
assert_eq 0 "$(ma_pow 5 3 1)" "ma_pow modulus one"
assert_fails "ma_pow rejects negative exponent" ma_pow 2 -1 7

# --- ma_inv ---------------------------------------------------------------
assert_eq 4 "$(ma_inv 2 7)" "ma_inv 2 mod 7"
assert_eq 1 "$(ma_inv 1 7)" "ma_inv of one"
assert_eq 1 "$(ma_inv 3 2)" "ma_inv 3 mod 2"
# a * inv(a) == 1 mod m, checked through ma_mul for the awkward large case.
inv=$(ma_inv 123456789 1000000007)
assert_eq 1 "$(ma_mul 123456789 "$inv" 1000000007)" "ma_inv round-trips through ma_mul"
assert_fails "ma_inv rejects non-coprime pair" ma_inv 4 8
assert_fails "ma_inv rejects zero modulus" ma_inv 3 0

# --- ma_hash_partition ----------------------------------------------------
assert_eq 2 "$(ma_hash_partition 10 4)" "hash_partition basic"
assert_eq 0 "$(ma_hash_partition 0 4)" "hash_partition zero key"
assert_eq 0 "$(ma_hash_partition 7 1)" "hash_partition single bucket"
assert_fails "hash_partition rejects zero buckets" ma_hash_partition 1 0
assert_fails "hash_partition rejects negative key" ma_hash_partition -1 4

printf '\n1..%d\n' "$((pass + fail))"
printf '# passed %d, failed %d\n' "$pass" "$fail"
if (( fail > 0 )); then
  exit 1
fi
exit 0
