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
        opts = [parse_int: unquote(format_in) in [:signed, :unsigned]]

        case Prefixed.to_format(unquote(input), "t_", unquote(format_out), opts) do
          {:ok, result} -> result
          result -> result
        end
        |> then(fn res -> assert unquote(output) == res end)
      end
    end
  end

  describe "init/1" do
    test "requires :prefix" do
      assert_raise ArgumentError, "option :prefix is required", fn ->
        Prefixed.init()
      end
    end

    test "rejects empty string prefix" do
      assert_raise ArgumentError, "option :prefix is required", fn ->
        Prefixed.init(prefix: "")
      end
    end

    test "rejects non-binary prefix" do
      assert_raise ArgumentError, "option :prefix is required", fn ->
        Prefixed.init(prefix: :atom)
      end
    end

    test "accepts unicode prefix" do
      assert %{prefix: "🔥_"} = Prefixed.init(prefix: "🔥_")
    end

    test "accepts prefix with special characters" do
      assert %{prefix: "user-id_"} = Prefixed.init(prefix: "user-id_")
      assert %{prefix: "usr.id_"} = Prefixed.init(prefix: "usr.id_")
      assert %{prefix: "usr id_"} = Prefixed.init(prefix: "usr id_")
    end

    test "accepts very long prefix" do
      long_prefix = String.duplicate("x", 100) <> "_"
      assert %{prefix: ^long_prefix} = Prefixed.init(prefix: long_prefix)
    end

    test "accepts prefix that resembles encoded data" do
      assert %{prefix: "AAAA_"} = Prefixed.init(prefix: "AAAA_")
      assert %{prefix: "f00d_"} = Prefixed.init(prefix: "f00d_")
    end

    test "sets defaults" do
      assert %{
               db_format: :signed,
               nonce_type: :counter,
               ex_format: :url64,
               no_noncense: Once,
               prefix: "t_",
               persist_prefix: false
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
      # "t_" prefix (<<116, 95>>) + 64-bit ID
      assert <<116, 95, _::64>> = raw
    end

    test "accepts and decodes hex-encoded when ex_format != int" do
      ambiguous = "t_1234567890123456"
      assert {:ok, raw} = Prefixed.cast(ambiguous, %{prefix: "t_", ex_format: :raw})
      # "t_" prefix + 64-bit ID
      assert <<116, 95, _::64>> = raw
    end

    test "accepts and decodes raw when ex_format != int" do
      ambiguous = "t_12345678"
      assert {:ok, raw} = Prefixed.cast(ambiguous, %{prefix: "t_", ex_format: :raw})
      # "t_" prefix + 64-bit ID
      assert <<116, 95, _::64>> = raw
    end

    test "accepts and decodes url64-encoded when ex_format == int" do
      ambiguous_int = 12_345_678_901
      ambiguous = "t_#{ambiguous_int}"

      assert {:ok, ambiguous} == Prefixed.cast(ambiguous, %{prefix: "t_", ex_format: :signed})
    end

    test "accepts and decodes hex-encoded when ex_format == int" do
      ambiguous_int = 1_234_567_890_123_456
      ambiguous = "t_#{ambiguous_int}"

      assert {:ok, ambiguous} == Prefixed.cast(ambiguous, %{prefix: "t_", ex_format: :unsigned})
    end

    test "accepts and decodes raw when ex_format == int" do
      ambiguous_int = 12_345_678
      ambiguous = "t_#{ambiguous_int}"

      assert {:ok, ambiguous} == Prefixed.cast(ambiguous, %{prefix: "t_", ex_format: :signed})
    end

    test "rejects unprefixed value" do
      assert :error = Prefixed.cast("AAAAAAAAAAA", %{prefix: "t_", ex_format: :url64})
      assert :error = Prefixed.cast("123", %{prefix: "t_", ex_format: :signed})
    end

    test "rejects wrong prefix" do
      assert :error = Prefixed.cast("wrong_AAAAAAAAAAA", %{prefix: "t_", ex_format: :url64})
      assert :error = Prefixed.cast("usr_AAAAAAAAAAA", %{prefix: "prod_", ex_format: :url64})
    end

    test "works with unicode prefix" do
      params = %{prefix: "🔥_", ex_format: :url64}
      assert {:ok, "🔥_AAAAAAAAAAA"} = Prefixed.cast("🔥_AAAAAAAAAAA", params)
    end

    test "works with special character prefix" do
      params = %{prefix: "user-id_", ex_format: :url64}
      assert {:ok, "user-id_AAAAAAAAAAA"} = Prefixed.cast("user-id_AAAAAAAAAAA", params)
    end

    test "works with very long prefix" do
      long_prefix = String.duplicate("x", 100) <> "_"
      params = %{prefix: long_prefix, ex_format: :url64}
      value = long_prefix <> "AAAAAAAAAAA"
      assert {:ok, ^value} = Prefixed.cast(value, params)
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

    test "rejects unprefixed value" do
      assert :error =
               Prefixed.dump("AAAAAAAAAAA", nil, %{
                 prefix: "t_",
                 ex_format: :url64,
                 db_format: :signed
               })

      assert :error =
               Prefixed.dump("123", nil, %{prefix: "t_", ex_format: :signed, db_format: :signed})
    end

    test "rejects wrong prefix" do
      assert :error =
               Prefixed.dump("wrong_AAAAAAAAAAA", nil, %{
                 prefix: "t_",
                 ex_format: :url64,
                 db_format: :signed
               })

      assert :error =
               Prefixed.dump("usr_AAAAAAAAAAA", nil, %{
                 prefix: "prod_",
                 ex_format: :url64,
                 db_format: :signed
               })
    end
  end

  describe "persist_prefix option" do
    test "validates db_format compatibility when persist_prefix is true" do
      assert_raise ArgumentError,
                   "option :persist_prefix requires db_format :raw, :hex or :url64",
                   fn ->
                     Prefixed.init(prefix: "t_", persist_prefix: true, db_format: :signed)
                   end

      assert_raise ArgumentError,
                   "option :persist_prefix requires db_format :raw, :hex or :url64",
                   fn ->
                     Prefixed.init(prefix: "t_", persist_prefix: true, db_format: :unsigned)
                   end
    end

    test "allows compatible db_formats when persist_prefix is true" do
      assert %{persist_prefix: true, db_format: :url64} =
               Prefixed.init(prefix: "t_", persist_prefix: true, db_format: :url64)

      assert %{persist_prefix: true, db_format: :hex} =
               Prefixed.init(prefix: "t_", persist_prefix: true, db_format: :hex)

      assert %{persist_prefix: true, db_format: :raw} =
               Prefixed.init(prefix: "t_", persist_prefix: true, db_format: :raw)
    end

    test "dump preserves prefix when persist_prefix is true" do
      params = Prefixed.init(prefix: "t_", persist_prefix: true, db_format: :url64)
      id = Prefixed.autogenerate(params)

      assert {:ok, dumped} = Prefixed.dump(id, nil, params)
      assert String.starts_with?(dumped, "t_")
      assert dumped == id
    end

    test "dump strips prefix when persist_prefix is false" do
      params = Prefixed.init(prefix: "t_", persist_prefix: false, db_format: :url64)
      id = Prefixed.autogenerate(params)

      assert {:ok, dumped} = Prefixed.dump(id, nil, params)
      refute String.starts_with?(dumped, "t_")
      assert dumped != id
    end

    test "load handles prefixed values when persist_prefix is true" do
      params =
        Prefixed.init(prefix: "t_", persist_prefix: true, db_format: :url64, ex_format: :url64)

      id = Prefixed.autogenerate(params)

      {:ok, dumped} = Prefixed.dump(id, nil, params)
      assert {:ok, loaded} = Prefixed.load(dumped, nil, params)
      assert loaded == id
      assert String.starts_with?(loaded, "t_")
    end

    test "load adds prefix when persist_prefix is false" do
      params =
        Prefixed.init(prefix: "t_", persist_prefix: false, db_format: :url64, ex_format: :url64)

      id = Prefixed.autogenerate(params)

      {:ok, dumped} = Prefixed.dump(id, nil, params)
      refute String.starts_with?(dumped, "t_")

      assert {:ok, loaded} = Prefixed.load(dumped, nil, params)
      assert loaded == id
      assert String.starts_with?(loaded, "t_")
    end

    test "round-trip with persist_prefix true for raw format" do
      params = Prefixed.init(prefix: "t_", persist_prefix: true, db_format: :raw, ex_format: :raw)
      id = Prefixed.autogenerate(params)

      {:ok, dumped} = Prefixed.dump(id, nil, params)
      {:ok, loaded} = Prefixed.load(dumped, nil, params)

      assert loaded == id
      assert <<116, 95, _::64>> = loaded
    end

    test "round-trip with persist_prefix true for hex format" do
      params = Prefixed.init(prefix: "t_", persist_prefix: true, db_format: :hex, ex_format: :hex)
      id = Prefixed.autogenerate(params)

      {:ok, dumped} = Prefixed.dump(id, nil, params)
      {:ok, loaded} = Prefixed.load(dumped, nil, params)

      assert loaded == id
      assert String.starts_with?(loaded, "t_")
    end

    test "load rejects values without prefix when persist_prefix is true" do
      params = Prefixed.init(prefix: "t_", persist_prefix: true, db_format: :url64)

      assert :error = Prefixed.load("AAAAAAAAAAA", nil, params)
    end

    test "cast preserves prefix when persist_prefix is true" do
      params =
        Prefixed.init(prefix: "t_", persist_prefix: true, db_format: :url64, ex_format: :url64)

      assert {:ok, casted} = Prefixed.cast("t_AAAAAAAAAAA", params)
      assert String.starts_with?(casted, "t_")
      assert casted == "t_AAAAAAAAAAA"
    end

    test "cast rejects values without prefix when persist_prefix is true" do
      params = Prefixed.init(prefix: "t_", persist_prefix: true, db_format: :url64)

      assert :error = Prefixed.cast("AAAAAAAAAAA", params)
    end

    test "cast returns prefixed value when persist_prefix is false" do
      params =
        Prefixed.init(prefix: "t_", persist_prefix: false, db_format: :signed, ex_format: :url64)

      {:ok, casted} = Prefixed.cast("t_AAAAAAAAAAA", params)
      # Cast adds prefix back, matching autogenerate and load behavior
      assert String.starts_with?(casted, "t_")
      assert casted == "t_AAAAAAAAAAA"
    end

    test "cast with format conversion when persist_prefix is true" do
      params =
        Prefixed.init(prefix: "t_", persist_prefix: true, db_format: :url64, ex_format: :hex)

      {:ok, casted} = Prefixed.cast("t_AAAAAAAAAAA", params)
      assert String.starts_with?(casted, "t_")
      assert casted == "t_0000000000000000"
    end
  end

  describe "to_format!/4" do
    test "raises on invalid input" do
      assert_raise ArgumentError, ~r/value could not be parsed/, fn ->
        Prefixed.to_format!("invalid", "t_", :signed)
      end
    end

    test "raises on wrong prefix" do
      assert_raise ArgumentError, ~r/value could not be parsed/, fn ->
        Prefixed.to_format!("wrong_AAAAAAAAAAA", "t_", :signed)
      end
    end

    test "raises on unprefixed value" do
      assert_raise ArgumentError, ~r/value could not be parsed/, fn ->
        Prefixed.to_format!("AAAAAAAAAAA", "t_", :signed)
      end
    end

    test "successfully converts valid prefixed values" do
      assert "t_0000000000000000" = Prefixed.to_format!("t_AAAAAAAAAAA", "t_", :hex)
    end
  end

  describe "load with corrupt data" do
    test "rejects corrupt prefixed data when persist_prefix is true" do
      params = Prefixed.init(prefix: "t_", persist_prefix: true, db_format: :url64)

      # Invalid url64 after prefix
      assert :error = Prefixed.load("t_!!invalid!!", nil, params)

      # Truncated data after prefix
      assert :error = Prefixed.load("t_AA", nil, params)
    end

    test "rejects data with wrong prefix when persist_prefix is true" do
      params = Prefixed.init(prefix: "t_", persist_prefix: true, db_format: :url64)

      assert :error = Prefixed.load("wrong_AAAAAAAAAAA", nil, params)
    end

    test "rejects unprefixed data when persist_prefix is true" do
      params = Prefixed.init(prefix: "t_", persist_prefix: true, db_format: :url64)

      assert :error = Prefixed.load("AAAAAAAAAAA", nil, params)
    end
  end
end
