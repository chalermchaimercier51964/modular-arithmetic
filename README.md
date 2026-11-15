# modular-arithmetic

Small shell library for modular exponentiation, modular inverses, and residues,
intended for checksums and hash partitioning where the numbers involved would
overflow bash's signed 64-bit arithmetic if multiplied naively.

## Usage

```bash
source modular_arithmetic.sh

# (2^1000) mod 1000000007
ma_pow 2 1000 1000000007        # prints 307473514

# inverse of 3 modulo 11
ma_inv 3 11                     # prints 4

# bucket for key 42 out of 16
ma_hash_partition 42 16         # prints 10
```

Every function prints its result on stdout and returns 0 on success. On bad
input it prints a diagnostic on stderr and returns 1, so `set -e` callers stop
immediately and `if ma_inv ...; then` works as expected.

## Why this exists

Bash arithmetic is signed 64-bit and wraps silently on overflow. A naive
`(( a * b % m ))` therefore gives wrong answers for the very inputs a checksum
or a hash partitioner is most likely to see. The library reduces operands
before combining them and uses double-and-add for multiplication, so the
intermediate values stay below `2*m` and cannot overflow as long as the modulus
is at most `2^62`. That bound is checked explicitly by `ma_mul`.

The trade-off is speed: double-and-add is O(log b) additions instead of one
hardware multiply. For the sizes that fit in a shell variable this is
negligible, and correctness under the standard arithmetic rules is worth more
than a micro-optimisation that only works until the numbers get interesting.

## Awkward edge

`ma_hash_partition` uses plain `key % buckets`. Adding or removing a bucket
remaps almost every key, which is the well-known weakness of modulo
partitioning. If you need minimal remapping, use consistent hashing instead;
this library deliberately does not implement it.

## API

- `ma_mod a m` — `a mod m`, with `0 <= result < m`.
- `ma_add a b m` — `(a + b) mod m`.
- `ma_mul a b m` — `(a * b) mod m`, overflow-safe for `m <= 2^62`.
- `ma_pow base exp m` — `(base ^ exp) mod m`.
- `ma_inv a m` — inverse of `a` modulo `m`; fails if `gcd(a, m) != 1`.
- `ma_hash_partition key buckets` — bucket index in `[0, buckets)`.

All arguments must be non-negative decimal integers. Moduli and bucket counts
must be positive. Passing anything else is an error, not a wraparound.

## Tests

```bash
bash test_modular_arithmetic.sh
```

The test script sources the library and calls its functions directly, so it
runs with no arguments and no external tools beyond coreutils and bash.
