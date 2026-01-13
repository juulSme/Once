# Changelog

All notable changes to this project will be documented in this file.

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
