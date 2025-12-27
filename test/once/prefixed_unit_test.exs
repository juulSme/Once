defmodule Once.PrefixedUnitTest do
  use ExUnit.Case, async: true
  alias Once.Prefixed
  doctest Prefixed

  @range Integer.pow(2, 64)
  @signed_min -Integer.pow(2, 63)
  @signed_max Integer.pow(2, 63) - 1
  @unsigned_max @range - 1
  @all_error Map.from_keys([:url64, :raw, :signed, :unsigned, :hex], :error)

  describe "to_format/2" do
    @format_tests [
                    %{
                      url64: "t_AAAAAAAAAAA",
                      raw: "t_" <> <<0, 0, 0, 0, 0, 0, 0, 0>>,
                      signed: "t_#{0}",
                      unsigned: "t_#{0}",
                      hex: "t_0000000000000000"
                    },
                    %{
                      url64: "t___________8",
                      raw: "t_" <> <<255, 255, 255, 255, 255, 255, 255, 255>>,
                      signed: "t_#{-1}",
                      unsigned: "t_#{@unsigned_max}",
                      hex: "t_ffffffffffffffff"
                    },
                    %{
                      url64: "t_f_________8",
                      raw: "t_" <> <<127, 255, 255, 255, 255, 255, 255, 255>>,
                      signed: "t_#{@signed_max}",
                      unsigned: "t_#{@signed_max}",
                      hex: "t_7fffffffffffffff"
                    },
                    %{
                      url64: "t_gAAAAAAAAAA",
                      raw: "t_" <> <<128, 0, 0, 0, 0, 0, 0, 0>>,
                      signed: "t_#{@signed_min}",
                      unsigned: "t_#{@signed_max + 1}",
                      hex: "t_8000000000000000"
                    }
                  ] ++
                    Enum.map(
                      # invalid inputs
                      [
                        "t_#{@range}",
                        "t_#{@signed_min - 1}",
                        "t_a",
                        "t_++++++++++A",
                        "t_XX12121212121212",
                        "AAAAAAAAAAA",
                        "1"
                      ],
                      &Map.put(@all_error, :invalid, &1)
                    )

    for formats_values <- @format_tests,
        {format_in, input} <- formats_values,
        {format_out, output} <- formats_values,
        input != :error and not (format_in == :invalid and format_out == :invalid) do
      test "should map [#{format_in}: #{inspect(input)}] to [#{format_out}: #{inspect(output)}]" do
        opts = [prefix: "t_", parse_int: unquote(format_in) in [:signed, :unsigned]]

        case Prefixed.to_format(unquote(input), unquote(format_out), opts) do
          {:ok, result} -> result
          result -> result
        end
        |> then(fn res -> assert unquote(output) == res end)
      end
    end
  end

  describe "init/1" do
    test "requires :prefix" do
      assert_raise ArgumentError, "you must provide :prefix", fn ->
        Prefixed.init()
      end
    end

    test "sets defaults" do
      assert %{
               db_format: :signed,
               nonce_type: :counter,
               ex_format: :url64,
               no_noncense: Once,
               prefix: "t_"
             } == Prefixed.init(prefix: "t_")
    end

    test "overrides defaults" do
      assert %{db_format: :url64, ex_format: :signed} =
               Prefixed.init(db_format: :url64, ex_format: :signed, prefix: "t_")
    end
  end

  test "cast/dump/load accept nil value" do
    opts = Prefixed.init(prefix: "t_")
    assert {:ok, nil} = Prefixed.cast(nil, opts)
    assert {:ok, nil} = Prefixed.dump(nil, %{}, opts)
    assert {:ok, nil} = Prefixed.load(nil, %{}, opts)
  end

  describe "autogenerate/1" do
    test "generates counter nonces in configured format" do
      params = Prefixed.init(prefix: "t_")

      assert <<116, 95, _::64>> = Map.put(params, :ex_format, :raw) |> Prefixed.autogenerate()
      assert <<116, 95, _::88>> = Map.put(params, :ex_format, :url64) |> Prefixed.autogenerate()

      assert <<116, 95, int::binary>> =
               Map.put(params, :ex_format, :signed) |> Prefixed.autogenerate()

      assert String.to_integer(int) |> to_string() == int
    end

    test "generates counter nonces" do
      params = Prefixed.init(prefix: "t_", ex_format: :raw)

      assert <<116, 95, ts1::42, _::22>> = Prefixed.autogenerate(params)
      Process.sleep(5)
      assert <<116, 95, ts2::42, _::22>> = Prefixed.autogenerate(params)
      assert ts1 == ts2
    end

    test "generates encrypted nonces in configured format" do
      params = Prefixed.init(prefix: "t_", nonce_type: :encrypted)

      assert <<116, 95, _::64>> = Map.put(params, :ex_format, :raw) |> Prefixed.autogenerate()
      assert <<116, 95, _::88>> = Map.put(params, :ex_format, :url64) |> Prefixed.autogenerate()

      assert <<116, 95, int::binary>> =
               Map.put(params, :ex_format, :signed) |> Prefixed.autogenerate()

      assert String.to_integer(int) |> to_string() == int
    end

    test "generates encrypted nonces" do
      params = Prefixed.init(prefix: "t_", nonce_type: :encrypted, ex_format: :raw)

      assert <<116, 95, ts1::42, _::22>> = Prefixed.autogenerate(params)
      assert <<116, 95, ts2::42, _::22>> = Prefixed.autogenerate(params)
      assert ts1 != ts2
    end

    test "generates sortable nonces" do
      params = Prefixed.init(prefix: "t_", nonce_type: :sortable, ex_format: :raw)

      assert <<116, 95, ts1::42, _::22>> = Prefixed.autogenerate(params)
      Process.sleep(5)
      assert <<116, 95, ts2::42, _::22>> = Prefixed.autogenerate(params)
      assert ts1 < ts2
    end
  end

  describe "cast/2" do
    test "accepts and decodes url64-encoded when ex_format != int" do
      ambiguous = "t_12345678901"
      assert {:ok, raw} = Prefixed.cast(ambiguous, %{prefix: "t_", ex_format: :raw})
      assert <<int::64>> = raw
      assert to_string(int) != ambiguous
    end

    test "accepts and decodes hex-encoded when ex_format != int" do
      ambiguous = "t_1234567890123456"
      assert {:ok, raw} = Prefixed.cast(ambiguous, %{prefix: "t_", ex_format: :raw})
      assert <<int::64>> = raw
      assert to_string(int) != ambiguous
    end

    test "accepts and decodes raw when ex_format != int" do
      ambiguous = "t_12345678"
      assert {:ok, raw} = Prefixed.cast(ambiguous, %{prefix: "t_", ex_format: :raw})
      assert <<int::64>> = raw
      assert to_string(int) != ambiguous
    end

    test "accepts and decodes url64-encoded when ex_format == int" do
      ambiguous_int = 12_345_678_901
      ambiguous = "t_#{ambiguous_int}"

      assert {:ok, ambiguous_int} ==
               Prefixed.cast("#{ambiguous}", %{prefix: "t_", ex_format: :unsigned})
    end

    test "accepts and decodes hex-encoded when ex_format == int" do
      ambiguous_int = 1_234_567_890_123_456
      ambiguous = "t_#{ambiguous_int}"

      assert {:ok, ambiguous_int} ==
               Prefixed.cast("#{ambiguous}", %{prefix: "t_", ex_format: :signed})
    end

    test "accepts and decodes raw when ex_format == int" do
      ambiguous_int = 12_345_678
      ambiguous = "t_#{ambiguous_int}"

      assert {:ok, ambiguous_int} ==
               Prefixed.cast("#{ambiguous}", %{prefix: "t_", ex_format: :unsigned})
    end
  end

  describe "dump/3" do
    test "accepts and decodes url64-encoded when ex_format != int" do
      ambiguous = "t_12345678901"

      assert {:ok, raw} =
               Prefixed.dump(ambiguous, nil, %{prefix: "t_", ex_format: :hex, db_format: :raw})

      assert <<int::64>> = raw
      assert to_string(int) != ambiguous
    end

    test "accepts and decodes hex-encoded when ex_format != int" do
      ambiguous = "t_1234567890123456"

      assert {:ok, raw} =
               Prefixed.dump(ambiguous, nil, %{prefix: "t_", ex_format: :hex, db_format: :raw})

      assert <<int::64>> = raw
      assert to_string(int) != ambiguous
    end

    test "accepts and decodes raw when ex_format != int" do
      ambiguous = "t_12345678"

      assert {:ok, raw} =
               Prefixed.dump(ambiguous, nil, %{prefix: "t_", ex_format: :hex, db_format: :raw})

      assert <<int::64>> = raw
      assert to_string(int) != ambiguous
    end

    test "accepts and decodes url64-encoded when ex_format == int" do
      ambiguous_int = 12_345_678_901
      ambiguous = "t_#{ambiguous_int}"

      assert {:ok, ambiguous_int} ==
               Prefixed.dump("#{ambiguous}", nil, %{
                 prefix: "t_",
                 ex_format: :unsigned,
                 db_format: :signed
               })
    end

    test "accepts and decodes hex-encoded when ex_format == int" do
      ambiguous_int = 1_234_567_890_123_456
      ambiguous = "t_#{ambiguous_int}"

      assert {:ok, ambiguous_int} ==
               Prefixed.dump("#{ambiguous}", nil, %{
                 prefix: "t_",
                 ex_format: :signed,
                 db_format: :signed
               })
    end

    test "accepts and decodes raw when ex_format == int" do
      ambiguous_int = 12_345_678
      ambiguous = "t_#{ambiguous_int}"

      assert {:ok, ambiguous_int} ==
               Prefixed.dump("#{ambiguous}", nil, %{
                 prefix: "t_",
                 ex_format: :unsigned,
                 db_format: :signed
               })
    end
  end
end
