defmodule OnceUnitTest do
  use ExUnit.Case, async: true
  doctest Once

  @range Integer.pow(2, 64)
  @signed_min -Integer.pow(2, 63)
  @signed_max Integer.pow(2, 63) - 1
  @unsigned_max @range - 1

  describe "to_format/3" do
    @format_tests [
      %{
        url64: "AAAAAAAAAAA",
        raw: <<0, 0, 0, 0, 0, 0, 0, 0>>,
        signed: 0,
        unsigned: 0,
        hex: "0000000000000000",
        hex32: "0000000000000"
      },
      %{
        url64: "__________8",
        raw: <<255, 255, 255, 255, 255, 255, 255, 255>>,
        signed: -1,
        unsigned: @unsigned_max,
        hex: "ffffffffffffffff",
        hex32: "vvvvvvvvvvvvu"
      },
      %{
        url64: "f_________8",
        raw: <<127, 255, 255, 255, 255, 255, 255, 255>>,
        signed: @signed_max,
        unsigned: @signed_max,
        hex: "7fffffffffffffff",
        hex32: "fvvvvvvvvvvvu"
      },
      %{
        url64: "gAAAAAAAAAA",
        raw: <<128, 0, 0, 0, 0, 0, 0, 0>>,
        signed: @signed_min,
        unsigned: @signed_max + 1,
        hex: "8000000000000000",
        hex32: "g000000000000"
      },
      # invalid inputs
      %{
        invalid: @range,
        url64: :error,
        raw: :error,
        signed: :error,
        unsigned: :error,
        hex: :error,
        hex32: :error
      },
      %{
        invalid: @signed_min - 1,
        url64: :error,
        raw: :error,
        signed: :error,
        unsigned: :error,
        hex: :error,
        hex32: :error
      },
      %{
        invalid: "a",
        url64: :error,
        raw: :error,
        signed: :error,
        unsigned: :error,
        hex: :error,
        hex32: :error
      },
      %{
        invalid: "++++++++++A",
        url64: :error,
        raw: :error,
        signed: :error,
        unsigned: :error,
        hex: :error,
        hex32: :error
      },
      %{
        invalid: "XX12121212121212",
        url64: :error,
        raw: :error,
        signed: :error,
        unsigned: :error,
        hex: :error,
        hex32: :error
      }
    ]

    for formats_values <- @format_tests,
        {format_in, input} <- formats_values,
        {format_out, output} <- formats_values,
        input != :error and not (format_in == :invalid and format_out == :invalid) do
      test "should map [#{format_in}: #{inspect(input)}] to [#{format_out}: #{inspect(output)}]" do
        case Once.to_format(unquote(input), unquote(format_out)) do
          {:ok, result} -> result
          result -> result
        end
        |> then(fn res -> assert unquote(output) == res end)
      end
    end
  end

  describe "init/1" do
    test "sets defaults" do
      assert %{
               db_format: :signed,
               nonce_type: :counter,
               ex_format: :url64,
               no_noncense: Once
             } == Once.init()
    end

    test "overrides defaults" do
      assert %{db_format: :url64, ex_format: :signed} =
               Once.init(db_format: :url64, ex_format: :signed)
    end

    test "validates options" do
      assert_raise ArgumentError, "option :no_noncense is invalid: \"boom\"", fn ->
        Once.init(no_noncense: "boom")
      end

      assert_raise ArgumentError, "option :ex_format is invalid: :invalid", fn ->
        Once.init(ex_format: :invalid)
      end

      assert_raise ArgumentError, "option :db_format is invalid: :invalid", fn ->
        Once.init(db_format: :invalid)
      end

      assert_raise ArgumentError, "option :nonce_type is invalid: :invalid", fn ->
        Once.init(nonce_type: :invalid)
      end

      assert_raise ArgumentError, "option :encrypt? is deprecated", fn ->
        Once.init(encrypt?: true)
      end

      assert_raise ArgumentError, "option :get_key is deprecated", fn ->
        Once.init(get_key: fn -> "key" end)
      end
    end
  end

  test "cast/dump/load accept nil value" do
    opts = Once.init()
    assert {:ok, nil} = Once.cast(nil, opts)
    assert {:ok, nil} = Once.dump(nil, %{}, opts)
    assert {:ok, nil} = Once.load(nil, %{}, opts)
  end

  describe "autogenerate/1" do
    test "generates counter nonces in configured format" do
      params = Once.init()

      assert <<_::64>> = Map.put(params, :ex_format, :raw) |> Once.autogenerate()
      assert <<_::88>> = Map.put(params, :ex_format, :url64) |> Once.autogenerate()
      int = Map.put(params, :ex_format, :signed) |> Once.autogenerate()
      assert is_integer(int)
    end

    test "generates counter nonces" do
      params = Once.init(ex_format: :raw)

      assert <<prefix1::42, _::22>> = Once.autogenerate(params)
      Process.sleep(5)
      assert <<prefix2::42, _::22>> = Once.autogenerate(params)
      assert prefix1 == prefix2
    end

    test "generates encrypted nonces in configured format" do
      params = Once.init(nonce_type: :encrypted)

      assert <<_::64>> = Map.put(params, :ex_format, :raw) |> Once.autogenerate()
      assert <<_::88>> = Map.put(params, :ex_format, :url64) |> Once.autogenerate()
      int = Map.put(params, :ex_format, :signed) |> Once.autogenerate()
      assert is_integer(int)
    end

    test "generates encrypted nonces" do
      params = Once.init(nonce_type: :encrypted, ex_format: :raw)

      assert <<prefix1::42, _::22>> = Once.autogenerate(params)
      assert <<prefix2::42, _::22>> = Once.autogenerate(params)
      assert prefix1 != prefix2
    end

    test "generates sortable nonces" do
      params = Once.init(nonce_type: :sortable, ex_format: :raw)

      assert <<prefix1::42, _::22>> = Once.autogenerate(params)
      Process.sleep(5)
      assert <<prefix2::42, _::22>> = Once.autogenerate(params)
      assert prefix1 < prefix2
    end
  end

  describe "cast/2" do
    test "accepts and decodes url64-encoded when ex_format != int" do
      ambiguous = "12345678901"
      assert {:ok, raw} = Once.cast(ambiguous, %{ex_format: :raw})
      assert <<int::64>> = raw
      assert to_string(int) != ambiguous
    end

    test "accepts and decodes hex-encoded when ex_format != int" do
      ambiguous = "1234567890123456"
      assert {:ok, raw} = Once.cast(ambiguous, %{ex_format: :raw})
      assert <<int::64>> = raw
      assert to_string(int) != ambiguous
    end

    test "accepts and decodes hex32-encoded when ex_format != int" do
      ambiguous = "1234567890123"
      assert {:ok, raw} = Once.cast(ambiguous, %{ex_format: :raw})
      assert <<int::64>> = raw
      assert to_string(int) != ambiguous
    end

    test "accepts and decodes raw when ex_format != int" do
      ambiguous = "12345678"
      assert {:ok, raw} = Once.cast(ambiguous, %{ex_format: :raw})
      assert <<int::64>> = raw
      assert to_string(int) != ambiguous
    end

    test "accepts and decodes url64-encoded when ex_format == int" do
      ambiguous = 12_345_678_901
      assert {:ok, ambiguous} == Once.cast("#{ambiguous}", %{ex_format: :unsigned})
    end

    test "accepts and decodes hex-encoded when ex_format == int" do
      ambiguous = 1_234_567_890_123_456
      assert {:ok, ambiguous} == Once.cast("#{ambiguous}", %{ex_format: :signed})
    end

    test "accepts and decodes hex32-encoded when ex_format == int" do
      ambiguous = 1_234_567_890_123
      assert {:ok, ambiguous} == Once.cast("#{ambiguous}", %{ex_format: :signed})
    end

    test "accepts and decodes raw when ex_format == int" do
      ambiguous = 12_345_678
      assert {:ok, ambiguous} == Once.cast("#{ambiguous}", %{ex_format: :unsigned})
    end

    test "rejects floats" do
      assert :error == Once.cast("1.2", %{ex_format: :unsigned})
      assert :error == Once.cast("1.0", %{ex_format: :unsigned})
    end
  end

  describe "dump/3" do
    test "accepts and decodes url64-encoded when ex_format != int" do
      ambiguous = "12345678901"
      assert {:ok, raw} = Once.dump(ambiguous, nil, %{ex_format: :hex, db_format: :raw})
      assert <<int::64>> = raw
      assert to_string(int) != ambiguous
    end

    test "accepts and decodes hex-encoded when ex_format != int" do
      ambiguous = "1234567890123456"
      assert {:ok, raw} = Once.dump(ambiguous, nil, %{ex_format: :hex, db_format: :raw})
      assert <<int::64>> = raw
      assert to_string(int) != ambiguous
    end

    test "accepts and decodes hex32-encoded when ex_format != int" do
      ambiguous = "1234567890123"
      assert {:ok, raw} = Once.dump(ambiguous, nil, %{ex_format: :hex32, db_format: :raw})
      assert <<int::64>> = raw
      assert to_string(int) != ambiguous
    end

    test "accepts and decodes raw when ex_format != int" do
      ambiguous = "12345678"
      assert {:ok, raw} = Once.dump(ambiguous, nil, %{ex_format: :hex, db_format: :raw})
      assert <<int::64>> = raw
      assert to_string(int) != ambiguous
    end

    test "accepts and decodes url64-encoded when ex_format == int" do
      ambiguous = 12_345_678_901

      assert {:ok, ambiguous} ==
               Once.dump("#{ambiguous}", nil, %{ex_format: :unsigned, db_format: :signed})
    end

    test "accepts and decodes hex-encoded when ex_format == int" do
      ambiguous = 1_234_567_890_123_456

      assert {:ok, ambiguous} ==
               Once.dump("#{ambiguous}", nil, %{ex_format: :signed, db_format: :signed})
    end

    test "accepts and decodes hex32-encoded when ex_format == int" do
      ambiguous = 1_234_567_890_123

      assert {:ok, ambiguous} ==
               Once.dump("#{ambiguous}", nil, %{ex_format: :signed, db_format: :signed})
    end

    test "accepts and decodes raw when ex_format == int" do
      ambiguous = 12_345_678

      assert {:ok, ambiguous} ==
               Once.dump("#{ambiguous}", nil, %{ex_format: :unsigned, db_format: :signed})
    end

    test "rejects floats" do
      assert :error == Once.dump("1.2", nil, %{ex_format: :unsigned})
      assert :error == Once.dump("1.0", nil, %{ex_format: :unsigned})
    end
  end
end
