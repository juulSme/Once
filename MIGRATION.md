# Migration Guide

## Upgrading to v1.0.0

Version 1.0.0 introduces breaking changes that follow from `NoNoncense` 1.0.0 breaking changes. Be sure to read its [migration guide](https://hexdocs.pm/no_noncense/migration.html).

**You only have to change anything if you are using encrypted IDs.**

In order to migrate to NoNoncense 1.x encrypted nonces without breaking its uniqueness guarantees, you **MUST NOT** change your key or cipher:

- pass your **existing** encryption key to `NoNoncense.init/1` new `:key64` option
- pass `:des3` to `NoNoncense.init/1` new `:cipher64` option

```elixir
# in application.ex (probably)
NoNoncense.init(
  name: Once,
  machine_id: NoNoncense.MachineId.id!(opts),
  cipher64: :des3,
  key64: System.get_env("ONCE_KEY")
)
```
