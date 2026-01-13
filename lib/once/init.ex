defmodule Once.Init do
  @moduledoc false
  use Once.Constants

  @doc """
  Verify all init opts.
  """
  def verify_init!(opts) do
    if not is_atom(opts.no_noncense) do
      raise ArgumentError, "option :no_noncense is invalid: #{inspect(opts.no_noncense)}"
    end

    if opts.ex_format not in @formats do
      raise ArgumentError, "option :ex_format is invalid: #{inspect(opts.ex_format)}"
    end

    if opts.db_format not in @formats do
      raise ArgumentError, "option :db_format is invalid: #{inspect(opts.db_format)}"
    end

    if opts.nonce_type not in [:counter, :encrypted, :sortable] do
      raise ArgumentError, "option :nonce_type is invalid: #{inspect(opts.nonce_type)}"
    end

    if not is_boolean(opts.mask) do
      raise ArgumentError, "option :mask must be a boolean"
    end

    if not is_boolean(opts.persist_prefix) do
      raise ArgumentError, "option :persist_prefix must be a boolean"
    end

    if opts.mask and opts.nonce_type == :encrypted do
      raise ArgumentError, "there is no point in masking encrypted nonces"
    end

    if not is_nil(opts.prefix) and not is_binary(opts.prefix) do
      raise ArgumentError, "option :prefix must be a binary"
    end

    if opts.persist_prefix and opts.db_format not in @binary_formats do
      raise ArgumentError,
            "option :persist_prefix requires db_format :raw, :hex, :hex32 or :url64"
    end

    if opts.prefix == "" do
      raise ArgumentError, "option :prefix can't be an empty string"
    end

    if opts.persist_prefix and not is_binary(opts.prefix) do
      raise ArgumentError, "option :persist_prefix can't be used without :prefix"
    end

    if is_map_key(opts, :encrypt?) do
      raise ArgumentError, "option :encrypt? is deprecated"
    end

    if is_map_key(opts, :get_key) do
      raise ArgumentError, "option :get_key is deprecated"
    end

    opts
  end
end
