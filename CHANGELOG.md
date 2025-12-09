# Changelog

All notable changes to this project will be documented in this file.

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
