defmodule Once.MaskedUnitTest do
  use ExUnit.Case, async: true
  use Once.Constants
  alias Once.Encode

  @base_opts Once.init(mask: true)

  defp encrypt(value), do: NoNoncense.encrypt(Once, value)
  defp decrypt(value), do: NoNoncense.decrypt(Once, value)

  test "cast/dump/load accept nil value" do
    opts = Once.init(@base_opts)
    assert {:ok, nil} = Once.cast(nil, opts)
    assert {:ok, nil} = Once.dump(nil, %{}, opts)
    assert {:ok, nil} = Once.load(nil, %{}, opts)
  end

  describe "init/1" do
    test "validates options" do
      assert_raise ArgumentError, "there is no point in masking encrypted nonces", fn ->
        Once.init(mask: true, nonce_type: :encrypted)
      end
    end
  end

  describe "autogenerate/1" do
    test "generates counter nonces in configured format" do
      params = Once.init(@base_opts)

      assert <<_::64>> = Map.put(params, :ex_format, :raw) |> Once.autogenerate()
      assert <<_::88>> = Map.put(params, :ex_format, :url64) |> Once.autogenerate()
      int = Map.put(params, :ex_format, :signed) |> Once.autogenerate()
      assert is_integer(int)
    end

    test "generates counter nonces" do
      params = Once.init(%{@base_opts | ex_format: :raw})

      assert <<prefix1::42, _::9, c1::13>> = Once.autogenerate(params) |> decrypt()
      assert <<prefix2::42, _::9, c2::13>> = Once.autogenerate(params) |> decrypt()
      assert prefix1 == prefix2
      assert c2 > c1
    end

    test "generates sortable nonces" do
      params = Once.init(%{@base_opts | nonce_type: :sortable, ex_format: :raw})

      assert <<prefix1::42, _::9, 0::13>> = Once.autogenerate(params) |> decrypt()
      Process.sleep(5)
      assert <<prefix2::42, _::9, 0::13>> = Once.autogenerate(params) |> decrypt()
      assert prefix1 < prefix2
    end
  end

  describe "dump/3" do
    test "accepts and decodes url64-encoded when ex_format != int" do
      ambiguous = "12345678901"

      assert {:ok, raw} =
               Once.dump(ambiguous, nil, %{@base_opts | ex_format: :hex, db_format: :raw})

      raw = encrypt(raw)
      assert <<int::64>> = raw
      assert to_string(int) != ambiguous
    end

    test "accepts and decodes hex-encoded when ex_format != int" do
      ambiguous = "1234567890123456"

      assert {:ok, raw} =
               Once.dump(ambiguous, nil, %{@base_opts | ex_format: :hex, db_format: :raw})

      raw = encrypt(raw)
      assert <<int::64>> = raw
      assert to_string(int) != ambiguous
    end

    test "accepts and decodes hex32-encoded when ex_format != int" do
      ambiguous = "1234567890123"

      assert {:ok, raw} =
               Once.dump(ambiguous, nil, %{@base_opts | ex_format: :hex32, db_format: :raw})

      raw = encrypt(raw)
      assert <<int::64>> = raw
      assert to_string(int) != ambiguous
    end

    test "accepts and decodes raw when ex_format != int" do
      ambiguous = "12345678"

      assert {:ok, raw} =
               Once.dump(ambiguous, nil, %{@base_opts | ex_format: :hex, db_format: :raw})

      raw = encrypt(raw)
      assert <<int::64>> = raw
      assert to_string(int) != ambiguous
    end

    test "accepts and decodes url64-encoded when ex_format == int" do
      ambiguous = 12_345_678_901

      assert {:ok, dumped} =
               Once.dump("#{ambiguous}", nil, %{
                 @base_opts
                 | ex_format: :unsigned,
                   db_format: :raw
               })

      assert <<ambiguous::64>> == encrypt(dumped)
    end

    test "accepts and decodes hex-encoded when ex_format == int" do
      ambiguous = 1_234_567_890_123_456

      assert {:ok, dumped} =
               Once.dump("#{ambiguous}", nil, %{
                 @base_opts
                 | ex_format: :signed,
                   db_format: :raw
               })

      assert <<ambiguous::64>> == encrypt(dumped)
    end

    test "accepts and decodes hex32-encoded when ex_format == int" do
      ambiguous = 1_234_567_890_123

      assert {:ok, dumped} =
               Once.dump("#{ambiguous}", nil, %{
                 @base_opts
                 | ex_format: :signed,
                   db_format: :raw
               })

      assert <<ambiguous::64>> == encrypt(dumped)
    end

    test "accepts and decodes raw when ex_format == int" do
      ambiguous = 12_345_678

      assert {:ok, dumped} =
               Once.dump("#{ambiguous}", nil, %{
                 @base_opts
                 | ex_format: :unsigned,
                   db_format: :raw
               })

      assert <<ambiguous::64>> == encrypt(dumped)
    end
  end

  describe "load/3" do
    test "accepts and decodes url64-encoded when ex_format != int" do
      ambiguous = "12345678901"

      assert {:ok, loaded} =
               Once.load(ambiguous, nil, %{@base_opts | ex_format: :raw, db_format: :url64})

      raw = decrypt(loaded)
      assert <<int::64>> = raw
      assert to_string(int) != ambiguous
    end

    test "accepts and decodes hex-encoded when ex_format != int" do
      ambiguous = "1234567890123456"

      assert {:ok, loaded} =
               Once.load(ambiguous, nil, %{@base_opts | ex_format: :raw, db_format: :hex})

      raw = decrypt(loaded)
      assert <<int::64>> = raw
      assert to_string(int) != ambiguous
    end

    test "accepts and decodes hex32-encoded when ex_format != int" do
      ambiguous = "1234567890123"

      assert {:ok, loaded} =
               Once.load(ambiguous, nil, %{@base_opts | ex_format: :raw, db_format: :hex32})

      raw = decrypt(loaded)
      assert <<int::64>> = raw
      assert to_string(int) != ambiguous
    end

    test "accepts and decodes raw when ex_format != int" do
      ambiguous = "12345678"

      assert {:ok, loaded} =
               Once.load(ambiguous, nil, %{@base_opts | ex_format: :raw, db_format: :raw})

      raw = decrypt(loaded)
      assert <<int::64>> = raw
      assert to_string(int) != ambiguous
    end
  end

  describe "round-trip" do
    test "preserves plaintext across formats and prefix configurations" do
      formats = [:url64, :hex, :hex32, :raw, :signed, :unsigned]
      prefix_options = [{nil, false}, {"t_", false}, {"t_", true}]

      for ex_format <- formats,
          db_format <- formats,
          {prefix, persist_prefix} <- prefix_options,
          plaintext <- [0, @signed_max, @signed_max + 1, @unsigned_max, 0x3132333435363738] do
        params =
          Once.init(
            mask: true,
            ex_format: ex_format,
            db_format: db_format,
            prefix: prefix,
            persist_prefix: persist_prefix
          )

        raw = <<plaintext::64>>
        id = raw |> encrypt() |> Once.to_format!(ex_format) |> Once.Prefix.put(prefix)
        db_value = Once.to_format!(raw, db_format)

        expected =
          if persist_prefix and db_format in @int_formats do
            digits = db_value |> abs() |> Integer.to_string() |> String.pad_leading(20, "0")
            prefix <> if(db_value < 0, do: "-" <> digits, else: digits)
          else
            Once.Prefix.put(db_value, if(persist_prefix, do: prefix))
          end

        assert {:ok, ^expected} = Once.dump(id, nil, params)
        assert {:ok, ^id} = Once.load(expected, nil, params)
      end
    end

    test "autogenerate → dump → load maintains plaintext value" do
      params = Once.init(%{@base_opts | ex_format: :url64, db_format: :signed})

      # Generate a masked ID
      masked_id = Once.autogenerate(params)
      {:ok, decoded} = masked_id |> Encode.decode64()
      plaintext = decoded |> decrypt()

      # Dump it (should decrypt to plaintext for DB)
      {:ok, db_value} = Once.dump(masked_id, nil, params)
      assert plaintext == <<db_value::signed-64>>

      # Load it back (should encrypt it again)
      {:ok, ^masked_id} = Once.load(db_value, nil, params)
    end
  end
end
