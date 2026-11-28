# Changelog

All notable changes to this project will be documented in this file.

## [2.2.0]

- Allow `persist_prefix: true` with integer `:db_format`s (`:signed`, `:unsigned`). The value is stored as a zero-padded decimal string (20 digits, plus a minus sign for negative values, for example `"usr_00000000000000000123"`), so the database column must be a string type. This combination previously raised an `ArgumentError`. Zero-padding keeps unsigned values sortable as strings; negative signed values do not sort numerically.
- Implement `Once.equal?/3` to compare IDs by their underlying value across accepted formats in Ecto changesets, respecting configured prefixes and integer parsing rules.
- Document the requirement to use one NoNoncense instance and nonce type for unique IDs.
- Fix loading binary database formats when the Elixir format is an integer.
- Reject stored IDs that do not decode to eight bytes in `Once.CreatedAt`.
- Document that non-canonical string IDs (uppercase `:hex`/`:hex32`, non-zero trailing bits in `:url64`/`:hex32`) are accepted and passed through unchanged, and how that affects `Once.Query`, ordering, lookups and uniqueness.
- Document how to protect against non-canonical string IDs: use different Elixir and database formats, canonicalize external input by converting through `:raw`, and check for uppercase rows.
- Add opt-in option `normalize: true` to re-encode `:url64`, `:hex` and `:hex32` values to their canonical spelling (lowercase hex, zeroed trailing bits) on cast, load and dump. Only enable it if your existing data is already canonical.
- Add `Once.Canonicalize`, migration helpers that rewrite stored `:hex`, `:hex32` and `:url64` IDs to their canonical spelling on PostgreSQL and MySQL. Listing the primary keys is enough: foreign keys that reference them (and persisted prefixes) are detected and changed along with them. `ecto_sql` is now an optional dependency, needed only to use `Once.Canonicalize.up/2`.
- Add `Once.Canonicalize.check/3` to check whether stored IDs need canonicalization without rewriting them.

## [2.1.0]

- Add `Once.Query` macros for filtering sortable IDs by generation time, including equality and custom epochs.
- Add `Once.CreatedAt`, a read-only Ecto type for exposing a sortable ID's generation time as a `DateTime`. Ecto 3.12 or later is recommended, as it enforces the field's read-only option.

## [2.0.0]

- Add NoNoncense 2.0 compatibility and adapt getting started guides.

## [1.3.1]

- Update hex description to advertise features better

## [1.3.0]

- Formulate an explicit support policy.
- Support Elixir 1.20 and Erlang/OTP 29.

## [1.2.2] (and [1.2.1])

Non-functional changes only.

- Add `Ecto Schema Integration` section to docs.
- Add `mix test.unit` to run base tests without a database.
- Minor code readability improvements.

## [1.2.0]

- Improve init opts verification:
  - `:mask` and `:persist_prefix` must be booleans
  - `:persist_prefix` requires `:prefix`

## [1.1.0]

- Add support for masked IDs using option `mask: true`.
- Merge `Once.Prefixed` into `Once` and soft-deprecate it. `Once` itself is a drop-in replacement.

## [1.0.0] - 2025-12-31

- Upgrade to NoNoncense >= 1.0, which has breaking changes. Be sure to read its [migration guide](https://hexdocs.pm/no_noncense/migration.html).
  - Hard deprecate options `:encrypt?` and `:get_key` (the NoNoncense encryption key is now passed to its `init/1` function)
- Add `Once.Prefixed` type for Stripe-style prefixed IDs (e.g., `"usr_AV7m9gAAAAU"`), with optional `:persist_prefix` to store prefix in database or strip it on storage
- Add support for base32hex encoding as format `:hex32`
- Require Elixir 1.16

## [0.1.0] - 2025-12-09

- Use Elixir 1.19 features when possible (`Base.valid64?/2`)
- Improve `Once.to_format/2` and `Once.to_format!/2` by adding a third opts param. Add option `:parse_int` to parse numeric strings to ints ("123" -> 123).
- Clarify docs on sorting order

## [0.0.8] - 2025-09-04

- Lowercase hex encoding

## [0.0.7] - 2025-01-17

- Re-arrange readme

## [0.0.6] - 2025-01-16

- Add numeric strings parsing when `:ex_format` is integer

## [0.0.5] - 2025-01-15

- Rename :type to :nonce_type to avoid clashing with Ecto's :belongs_to opts
- Base type/1 output on :db_format instead of :ex_format

## [0.0.4] - 2025-01-13

- Add sortable nonce support

## [0.0.3] - 2025-01-08

- Change name of format :encoded to :url64, add format :hex

## [0.0.2] - 2025-01-08

- Improve documentation

## [0.0.1] - 2025-01-08

- Initial release
