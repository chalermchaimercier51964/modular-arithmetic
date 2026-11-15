#!/usr/bin/env bash
# modular_arithmetic.sh -- modular arithmetic helpers for checksums and hash partitioning.
#
# All functions operate on non-negative integers that fit in bash's signed 64-bit
# arithmetic. The modulus must be positive. Inputs are validated eagerly so that
# callers get a clear error instead of a silent wraparound.
#
# The functions are deliberately pure: they print their result to stdout and
# return 0 on success, or print an error to stderr and return 1 on failure.
# That makes them easy to compose with command substitution and with `set -e`.

set -euo pipefail

# _ma_die prints a message to stderr and returns 1.
_ma_die() {
  printf 'modular_arithmetic: %s\n' "$1" >&2
  return 1
}

# _ma_is_uint returns 0 if the argument is a non-empty string of decimal digits,
# 1 otherwise. We deliberately reject signs, whitespace, and leading '+':
# accepting them would make the contract fuzzy and hide caller bugs.
_ma_is_uint() {
  local s=$1
  [[ -n $s && $s =~ ^[0-9]+$ ]]
}

# ma_mod a m -> prints a mod m.
#
# The modulus must be positive. The dividend may be any non-negative integer.
# Bash's `%` already satisfies 0 <= result < m for these inputs, so we only
# need to validate.
ma_mod() {
  local a=$1 m=$2
  _ma_is_uint "$a" || { _ma_die "ma_mod: dividend must be a non-negative integer, got '$a'"; return 1; }
  _ma_is_uint "$m" || { _ma_die "ma_mod: modulus must be a non-negative integer, got '$m'"; return 1; }
  (( m > 0 )) || { _ma_die "ma_mod: modulus must be positive, got $m"; return 1; }
  printf '%s\n' "$(( a % m ))"
}

# ma_add a b m -> prints (a + b) mod m.
#
# We reduce each operand first, then add. Reducing first keeps the intermediate
# sum below 2*m, which avoids overflow for the largest inputs bash can represent.
ma_add() {
  local a=$1 b=$2 m=$3
  local ra rb
  ra=$(ma_mod "$a" "$m") || return 1
  rb=$(ma_mod "$b" "$m") || return 1
  printf '%s\n' "$(( (ra + rb) % m ))"
}

# ma_mul a b m -> prints (a * b) mod m.
#
# Bash arithmetic is signed 64-bit. For large a and b the product overflows and
# silently wraps, which is exactly the kind of bug this library exists to avoid.
# We use the standard double-and-add (Russian peasant) method: it only needs
# additions and doublings, both of which stay below 2*m and therefore cannot
# overflow when m is at most 2^62.
ma_mul() {
  local a=$1 b=$2 m=$3
  local ra rb result
  ra=$(ma_mod "$a" "$m") || return 1
  rb=$(ma_mod "$b" "$m") || return 1
  (( m <= 4611686018427387904 )) || { _ma_die "ma_mul: modulus too large for safe multiplication, got $m"; return 1; }
  result=0
  while (( rb > 0 )); do
    if (( rb & 1 )); then
      result=$(( (result + ra) % m ))
    fi
    ra=$(( (ra * 2) % m ))
    rb=$(( rb >> 1 ))
  done
  printf '%s\n' "$result"
}

# ma_pow base exp m -> prints (base ^ exp) mod m.
#
# Square-and-multiply. ma_mul is used for every multiplication so the same
# overflow guarantee applies. exp == 0 returns 1 mod m, including m == 1 where
# the answer is 0; that is the standard convention.
ma_pow() {
  local base=$1 exp=$2 m=$3
  local r b e
  r=$(ma_mod "$base" "$m") || return 1
  _ma_is_uint "$exp" || { _ma_die "ma_pow: exponent must be a non-negative integer, got '$exp'"; return 1; }
  b=$r
  e=$exp
  r=1
  r=$(ma_mod "$r" "$m") || return 1
  while (( e > 0 )); do
    if (( e & 1 )); then
      r=$(ma_mul "$r" "$b" "$m") || return 1
    fi
    b=$(ma_mul "$b" "$b" "$m") || return 1
    e=$(( e >> 1 ))
  done
  printf '%s\n' "$r"
}

# _ma_gcd a b -> prints the greatest common divisor of a and b.
# Iterative Euclid; a and b must be non-negative integers.
_ma_gcd() {
  local a=$1 b=$2 t
  while (( b != 0 )); do
    t=$(( a % b ))
    a=$b
    b=$t
  done
  printf '%s\n' "$a"
}

# _ma_egcd a b -> prints "g x y" where g = gcd(a,b) and a*x + b*y = g.
# The extended Euclidean algorithm, iterative form.
_ma_egcd() {
  local a=$1 b=$2
  local old_r r old_s s old_t t q tmp
  old_r=$a; r=$b
  old_s=1; s=0
  old_t=0; t=1
  while (( r != 0 )); do
    q=$(( old_r / r ))
    tmp=$(( old_r - q * r )); old_r=$r; r=$tmp
    tmp=$(( old_s - q * s )); old_s=$s; s=$tmp
    tmp=$(( old_t - q * t )); old_t=$t; t=$tmp
  done
  printf '%s %s %s\n' "$old_r" "$old_s" "$old_t"
}

# ma_inv a m -> prints the modular inverse of a modulo m, or fails if none
# exists. The inverse exists exactly when gcd(a, m) == 1. m must be positive.
ma_inv() {
  local a=$1 m=$2
  local g x
  local out
  _ma_is_uint "$m" || { _ma_die "ma_inv: modulus must be a non-negative integer, got '$m'"; return 1; }
  (( m > 0 )) || { _ma_die "ma_inv: modulus must be positive, got $m"; return 1; }
  _ma_is_uint "$a" || { _ma_die "ma_inv: value must be a non-negative integer, got '$a'"; return 1; }
  a=$(( a % m ))
  out=$(_ma_egcd "$a" "$m")
  # shellcheck disable=SC2086 # we want word splitting here
  set -- $out
  g=$1
  x=$2
  if (( g != 1 )); then
    _ma_die "ma_inv: $a has no inverse modulo $m (gcd is $g)"
    return 1
  fi
  # x may be negative; normalise into [0, m).
  printf '%s\n' "$(( (x % m + m) % m ))"
}

# ma_hash_partition key buckets -> prints the bucket index for key in [0, buckets).
#
# This is the classic "modulo" partitioning rule. It is cheap and stable, but
# it remaps almost every key when the bucket count changes; consistent hashing
# exists precisely to avoid that. We document the trade-off rather than pretend
# otherwise.
ma_hash_partition() {
  local key=$1 buckets=$2
  _ma_is_uint "$key" || { _ma_die "ma_hash_partition: key must be a non-negative integer, got '$key'"; return 1; }
  _ma_is_uint "$buckets" || { _ma_die "ma_hash_partition: bucket count must be a non-negative integer, got '$buckets'"; return 1; }
  (( buckets > 0 )) || { _ma_die "ma_hash_partition: bucket count must be positive, got $buckets"; return 1; }
  printf '%s\n' "$(( key % buckets ))"
}
