defmodule OnceUnitTest do
  use ExUnit.Case, async: true
  doctest Once

  @range Integer.pow(2, 64)
  @signed_min -Integer.pow(2, 63)
  @signed_max Integer.pow(2, 63) - 1
  @unsigned_max @range - 1

  describe "to_format/2" do
    @format_tests [
      %{
        url64: "AAAAAAAAAAA",
        raw: <<0, 0, 0, 0, 0, 0, 0, 0>>,
        signed: 0,
        unsigned: 0,
        hex: "0000000000000000",
        base32: "aaaaaaaaaaaaa"
      },
      %{
        url64: "__________8",
        raw: <<255, 255, 255, 255, 255, 255, 255, 255>>,
        signed: -1,
        unsigned: @unsigned_max,
        hex: "ffffffffffffffff",
        base32: "7777777777776"
      },
      %{
        url64: "f_________8",
        raw: <<127, 255, 255, 255, 255, 255, 255, 255>>,
        signed: @signed_max,
        unsigned: @signed_max,
        hex: "7fffffffffffffff",
        base32: "p777777777776"
      },
      %{
        url64: "gAAAAAAAAAA",
        raw: <<128, 0, 0, 0, 0, 0, 0, 0>>,
        signed: @signed_min,
        unsigned: @signed_max + 1,
        hex: "8000000000000000"
      },
      # invalid inputs
      %{
        invalid: @range,
        url64: :error,
        raw: :error,
        signed: :error,
        unsigned: :error,
        hex: :error,
        base32: :error
      },
      %{
        invalid: @signed_min - 1,
        url64: :error,
        raw: :error,
        signed: :error,
        unsigned: :error,
        hex: :error,
        base32: :error
      },
      %{
        invalid: "a",
        url64: :error,
        raw: :error,
        signed: :error,
        unsigned: :error,
        hex: :error,
        base32: :error
      },
      %{
        invalid: "++++++++++A",
        url64: :error,
        raw: :error,
        signed: :error,
        unsigned: :error,
        hex: :error,
        base32: :error
      },
      %{
        invalid: "XX12121212121212",
        url64: :error,
        raw: :error,
        signed: :error,
        unsigned: :error,
        hex: :error,
        base32: :error
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
    @tag :capture_log
    test "requires get_key if :encrypt? == true" do
      assert_raise ArgumentError, "you must provide :get_key", fn ->
        Once.init(encrypt?: true)
      end
    end

    test "logs deprecation warning for encrypt?" do
      {_, log} =
        ExUnit.CaptureLog.with_log(fn ->
          Once.init(encrypt?: true, get_key: fn -> :crypto.strong_rand_bytes(24) end)
        end)

      assert log =~
               "[warning] option `:encrypt?` is deprecated, use `nonce_type: :encrypted` instead"
    end

    test "requires get_key if :type == :encrypted" do
      assert_raise ArgumentError, "you must provide :get_key", fn ->
        Once.init(nonce_type: :encrypted)
      end
    end

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
      params = Once.init(nonce_type: :encrypted, get_key: fn -> :crypto.strong_rand_bytes(24) end)

      assert <<_::64>> = Map.put(params, :ex_format, :raw) |> Once.autogenerate()
      assert <<_::88>> = Map.put(params, :ex_format, :url64) |> Once.autogenerate()
      int = Map.put(params, :ex_format, :signed) |> Once.autogenerate()
      assert is_integer(int)
    end

    test "generates encrypted nonces" do
      params =
        Once.init(
          nonce_type: :encrypted,
          get_key: fn -> :crypto.strong_rand_bytes(24) end,
          ex_format: :raw
        )

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

    test "accepts and decodes base32-encoded when ex_format == int" do
      ambiguous = 1_234_567_890_123
      assert {:ok, ambiguous} == Once.cast("#{ambiguous}", %{ex_format: :signed})
    end

    test "accepts and decodes raw when ex_format == int" do
      ambiguous = 12_345_678
      assert {:ok, ambiguous} == Once.cast("#{ambiguous}", %{ex_format: :unsigned})
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

    test "accepts and decodes raw when ex_format == int" do
      ambiguous = 12_345_678

      assert {:ok, ambiguous} ==
               Once.dump("#{ambiguous}", nil, %{ex_format: :unsigned, db_format: :signed})
    end
  end
end
