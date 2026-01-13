defmodule Once.PrefixedUnitTest do
  use ExUnit.Case, async: true
  use Once.Constants

  @all_error Map.from_keys([:url64, :raw, :signed, :unsigned, :hex], :error)
  @base_opts Once.init(prefix: "t_")

  describe "to_format/2" do
    @format_tests [
                    %{
                      url64: "t_AAAAAAAAAAA",
                      raw: "t_" <> <<0, 0, 0, 0, 0, 0, 0, 0>>,
                      signed: "t_#{0}",
                      unsigned: "t_#{0}",
                      hex: "t_0000000000000000",
                      hex32: "t_0000000000000"
                    },
                    %{
                      url64: "t___________8",
                      raw: "t_" <> <<255, 255, 255, 255, 255, 255, 255, 255>>,
                      signed: "t_#{-1}",
                      unsigned: "t_#{@unsigned_max}",
                      hex: "t_ffffffffffffffff",
                      hex32: "t_vvvvvvvvvvvvu"
                    },
                    %{
                      url64: "t_f_________8",
                      raw: "t_" <> <<127, 255, 255, 255, 255, 255, 255, 255>>,
                      signed: "t_#{@signed_max}",
                      unsigned: "t_#{@signed_max}",
                      hex: "t_7fffffffffffffff",
                      hex32: "t_fvvvvvvvvvvvu"
                    },
                    %{
                      url64: "t_gAAAAAAAAAA",
                      raw: "t_" <> <<128, 0, 0, 0, 0, 0, 0, 0>>,
                      signed: "t_#{@signed_min}",
                      unsigned: "t_#{@signed_max + 1}",
                      hex: "t_8000000000000000",
                      hex32: "t_g000000000000"
                    }
                  ] ++
                    Enum.map(
                      # invalid inputs
                      [
                        "t_#{@bigint_size}",
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
        opts = [parse_int: unquote(format_in) in [:signed, :unsigned], prefix: "t_"]

        case Once.to_format(unquote(input), unquote(format_out), opts) do
          {:ok, result} -> result
          result -> result
        end
        |> then(fn res -> assert unquote(output) == res end)
      end
    end
  end

  describe "init/1" do
    test "rejects empty string prefix" do
      assert_raise ArgumentError, "option :prefix can't be an empty string", fn ->
        Once.init(prefix: "")
      end
    end

    test "rejects non-binary prefix" do
      assert_raise ArgumentError, "option :prefix must be a binary", fn ->
        Once.init(prefix: :atom)
      end
    end

    test "validates db_format compatibility when persist_prefix is true" do
      for fmt <- @int_formats do
        assert_raise ArgumentError,
                     "option :persist_prefix requires db_format :raw, :hex, :hex32 or :url64",
                     fn ->
                       Once.init(prefix: "t_", persist_prefix: true, db_format: fmt)
                     end
      end
    end

    test "allows compatible db_formats when persist_prefix is true" do
      for fmt <- @binary_formats do
        Once.init(prefix: "t_", persist_prefix: true, db_format: fmt)
      end
    end

    test "reject :persist_prefix without :prefix" do
      assert_raise ArgumentError, "option :persist_prefix can't be used without :prefix", fn ->
        Once.init(persist_prefix: true, db_format: :hex)
      end
    end
  end

  describe "autogenerate/1" do
    test "generates counter nonces in configured format" do
      assert <<"t_", _::64>> = %{@base_opts | ex_format: :raw} |> Once.autogenerate()
      assert <<"t_", _::88>> = %{@base_opts | ex_format: :url64} |> Once.autogenerate()
      assert <<"t_", int::binary>> = %{@base_opts | ex_format: :signed} |> Once.autogenerate()

      assert String.to_integer(int) |> to_string() == int
    end

    test "generates counter nonces" do
      params = %{@base_opts | ex_format: :raw}

      assert <<"t_", ts1::42, _::9, c1::13>> = Once.autogenerate(params)
      Process.sleep(5)
      assert <<"t_", ts2::42, _::9, c2::13>> = Once.autogenerate(params)
      assert ts1 == ts2
      assert c2 > c1
    end

    test "generates encrypted nonces in configured format" do
      params = %{@base_opts | nonce_type: :encrypted}

      assert <<"t_", _::64>> = %{params | ex_format: :raw} |> Once.autogenerate()
      assert <<"t_", _::88>> = %{params | ex_format: :url64} |> Once.autogenerate()
      assert <<"t_", int::binary>> = %{params | ex_format: :signed} |> Once.autogenerate()

      assert String.to_integer(int) |> to_string() == int
    end

    test "generates encrypted nonces" do
      params = %{@base_opts | nonce_type: :encrypted, ex_format: :raw}

      assert <<"t_", ts1::42, _::22>> = Once.autogenerate(params)
      assert <<"t_", ts2::42, _::22>> = Once.autogenerate(params)
      assert ts1 != ts2
    end

    test "generates sortable nonces" do
      params = %{@base_opts | nonce_type: :sortable, ex_format: :raw}

      assert <<"t_", ts1::42, _::9, 0::13>> = Once.autogenerate(params)
      Process.sleep(5)
      assert <<"t_", ts2::42, _::9, 0::13>> = Once.autogenerate(params)
      assert ts1 < ts2
    end
  end

  describe "cast/2" do
    test "accepts and decodes url64-encoded when ex_format != int" do
      ambiguous = "t_12345678901"
      assert {:ok, raw} = Once.cast(ambiguous, %{@base_opts | ex_format: :raw})
      # "t_" prefix (<<"t_">>) + 64-bit ID
      assert <<"t_", _::64>> = raw
    end

    test "accepts and decodes hex-encoded when ex_format != int" do
      ambiguous = "t_1234567890123456"
      assert {:ok, raw} = Once.cast(ambiguous, %{@base_opts | ex_format: :raw})
      # "t_" prefix + 64-bit ID
      assert <<"t_", _::64>> = raw
    end

    test "accepts and decodes hex32-encoded when ex_format != int" do
      ambiguous = "t_1234567890123"
      assert {:ok, raw} = Once.cast(ambiguous, %{@base_opts | ex_format: :raw})
      # "t_" prefix + 64-bit ID
      assert <<"t_", _::64>> = raw
    end

    test "accepts and decodes raw when ex_format != int" do
      ambiguous = "t_12345678"
      assert {:ok, raw} = Once.cast(ambiguous, %{@base_opts | ex_format: :raw})
      # "t_" prefix + 64-bit ID
      assert <<"t_", _::64>> = raw
    end

    test "accepts and decodes url64-encoded when ex_format == int" do
      ambiguous_int = 12_345_678_901
      ambiguous = "t_#{ambiguous_int}"

      assert {:ok, ambiguous} == Once.cast(ambiguous, %{@base_opts | ex_format: :signed})
    end

    test "accepts and decodes hex-encoded when ex_format == int" do
      ambiguous_int = 1_234_567_890_123_456
      ambiguous = "t_#{ambiguous_int}"

      assert {:ok, ambiguous} == Once.cast(ambiguous, %{@base_opts | ex_format: :unsigned})
    end

    test "accepts and decodes hex32-encoded when ex_format == int" do
      ambiguous_int = 1_234_567_890_123
      ambiguous = "t_#{ambiguous_int}"

      assert {:ok, ambiguous} == Once.cast(ambiguous, %{@base_opts | ex_format: :unsigned})
    end

    test "accepts and decodes raw when ex_format == int" do
      ambiguous_int = 12_345_678
      ambiguous = "t_#{ambiguous_int}"

      assert {:ok, ambiguous} == Once.cast(ambiguous, %{@base_opts | ex_format: :signed})
    end

    test "rejects unprefixed value" do
      assert :error = Once.cast("AAAAAAAAAAA", %{@base_opts | ex_format: :url64})
      assert :error = Once.cast("123", %{@base_opts | ex_format: :signed})
    end

    test "rejects wrong prefix" do
      assert :error = Once.cast("wrong_AAAAAAAAAAA", %{@base_opts | ex_format: :url64})
      assert :error = Once.cast("usr_AAAAAAAAAAA", %{prefix: "prod_", ex_format: :url64})
    end
  end

  describe "dump/3" do
    test "accepts and decodes url64-encoded when ex_format != int" do
      ambiguous = "t_12345678901"

      assert {:ok, raw} =
               Once.dump(ambiguous, nil, %{@base_opts | ex_format: :hex, db_format: :raw})

      assert <<int::64>> = raw
      assert to_string(int) != ambiguous
    end

    test "accepts and decodes hex-encoded when ex_format != int" do
      ambiguous = "t_1234567890123456"

      assert {:ok, raw} =
               Once.dump(ambiguous, nil, %{@base_opts | ex_format: :hex, db_format: :raw})

      assert <<int::64>> = raw
      assert to_string(int) != ambiguous
    end

    test "accepts and decodes hex32-encoded when ex_format != int" do
      ambiguous = "t_1234567890123"

      assert {:ok, raw} =
               Once.dump(ambiguous, nil, %{@base_opts | ex_format: :hex32, db_format: :raw})

      assert <<int::64>> = raw
      assert to_string(int) != ambiguous
    end

    test "accepts and decodes raw when ex_format != int" do
      ambiguous = "t_12345678"

      assert {:ok, raw} =
               Once.dump(ambiguous, nil, %{@base_opts | ex_format: :hex, db_format: :raw})

      assert <<int::64>> = raw
      assert to_string(int) != ambiguous
    end

    test "accepts and decodes url64-encoded when ex_format == int" do
      ambiguous_int = 12_345_678_901
      ambiguous = "t_#{ambiguous_int}"

      assert {:ok, ambiguous_int} ==
               Once.dump("#{ambiguous}", nil, %{
                 @base_opts
                 | ex_format: :unsigned,
                   db_format: :signed
               })
    end

    test "accepts and decodes hex-encoded when ex_format == int" do
      ambiguous_int = 1_234_567_890_123_456
      ambiguous = "t_#{ambiguous_int}"

      assert {:ok, ambiguous_int} ==
               Once.dump("#{ambiguous}", nil, %{
                 @base_opts
                 | ex_format: :signed,
                   db_format: :signed
               })
    end

    test "accepts and decodes hex32-encoded when ex_format == int" do
      ambiguous_int = 1_234_567_890_123
      ambiguous = "t_#{ambiguous_int}"

      assert {:ok, ambiguous_int} ==
               Once.dump("#{ambiguous}", nil, %{
                 @base_opts
                 | ex_format: :signed,
                   db_format: :signed
               })
    end

    test "accepts and decodes raw when ex_format == int" do
      ambiguous_int = 12_345_678
      ambiguous = "t_#{ambiguous_int}"

      assert {:ok, ambiguous_int} ==
               Once.dump("#{ambiguous}", nil, %{
                 @base_opts
                 | ex_format: :unsigned,
                   db_format: :signed
               })
    end

    test "rejects unprefixed value" do
      assert :error =
               Once.dump("AAAAAAAAAAA", nil, %{
                 @base_opts
                 | ex_format: :url64,
                   db_format: :signed
               })

      assert :error =
               Once.dump("123", nil, %{@base_opts | ex_format: :signed, db_format: :signed})
    end

    test "rejects wrong prefix" do
      assert :error =
               Once.dump("wrong_AAAAAAAAAAA", nil, %{
                 @base_opts
                 | ex_format: :url64,
                   db_format: :signed
               })

      assert :error =
               Once.dump("usr_AAAAAAAAAAA", nil, %{
                 @base_opts
                 | prefix: "prod_",
                   ex_format: :url64,
                   db_format: :signed
               })
    end
  end

  describe "persist_prefix option" do
    test "dump preserves prefix when persist_prefix is true" do
      params = %{@base_opts | persist_prefix: true, db_format: :url64}
      id = Once.autogenerate(params)

      assert {:ok, dumped} = Once.dump(id, nil, params)
      assert String.starts_with?(dumped, "t_")
      assert dumped == id
    end

    test "dump strips prefix when persist_prefix is false" do
      params = %{@base_opts | persist_prefix: false, db_format: :url64}
      id = Once.autogenerate(params)

      assert {:ok, dumped} = Once.dump(id, nil, params)
      refute String.starts_with?(dumped, "t_")
      assert dumped != id
    end

    test "load handles prefixed values when persist_prefix is true" do
      params = %{@base_opts | persist_prefix: true, db_format: :url64, ex_format: :url64}
      id = Once.autogenerate(params)

      {:ok, dumped} = Once.dump(id, nil, params)
      assert {:ok, loaded} = Once.load(dumped, nil, params)
      assert loaded == id
      assert String.starts_with?(loaded, "t_")
    end

    test "load adds prefix when persist_prefix is false" do
      params = %{@base_opts | persist_prefix: false, db_format: :url64, ex_format: :url64}
      id = Once.autogenerate(params)

      {:ok, dumped} = Once.dump(id, nil, params)
      refute String.starts_with?(dumped, "t_")

      assert {:ok, loaded} = Once.load(dumped, nil, params)
      assert loaded == id
      assert String.starts_with?(loaded, "t_")
    end

    test "round-trip with persist_prefix true for raw format" do
      params = %{@base_opts | persist_prefix: true, db_format: :raw, ex_format: :raw}
      id = Once.autogenerate(params)

      {:ok, dumped} = Once.dump(id, nil, params)
      {:ok, loaded} = Once.load(dumped, nil, params)

      assert loaded == id
      assert <<"t_", _::64>> = loaded
    end

    test "round-trip with persist_prefix true for hex format" do
      params = %{@base_opts | persist_prefix: true, db_format: :hex, ex_format: :hex}
      id = Once.autogenerate(params)

      {:ok, dumped} = Once.dump(id, nil, params)
      {:ok, loaded} = Once.load(dumped, nil, params)

      assert loaded == id
      assert String.starts_with?(loaded, "t_")
    end

    test "round-trip with persist_prefix true for hex32 format" do
      params = %{@base_opts | persist_prefix: true, db_format: :hex32, ex_format: :hex32}
      id = Once.autogenerate(params)

      {:ok, dumped} = Once.dump(id, nil, params)
      {:ok, loaded} = Once.load(dumped, nil, params)

      assert loaded == id
      assert String.starts_with?(loaded, "t_")
    end

    test "load rejects values without prefix when persist_prefix is true" do
      params = %{@base_opts | persist_prefix: true, db_format: :url64}
      assert :error = Once.load("AAAAAAAAAAA", nil, params)
    end

    test "cast preserves prefix when persist_prefix is true" do
      params = %{@base_opts | persist_prefix: true, db_format: :url64, ex_format: :url64}
      assert {:ok, casted} = Once.cast("t_AAAAAAAAAAA", params)
      assert String.starts_with?(casted, "t_")
      assert casted == "t_AAAAAAAAAAA"
    end

    test "cast rejects values without prefix when persist_prefix is true" do
      params = %{@base_opts | persist_prefix: true, db_format: :url64}
      assert :error = Once.cast("AAAAAAAAAAA", params)
    end

    test "cast returns prefixed value when persist_prefix is false" do
      params = %{@base_opts | persist_prefix: false, db_format: :signed, ex_format: :url64}
      {:ok, casted} = Once.cast("t_AAAAAAAAAAA", params)
      # Cast adds prefix back, matching autogenerate and load behavior
      assert String.starts_with?(casted, "t_")
      assert casted == "t_AAAAAAAAAAA"
    end

    test "cast with format conversion when persist_prefix is true" do
      params = %{@base_opts | persist_prefix: true, db_format: :url64, ex_format: :hex}
      {:ok, casted} = Once.cast("t_AAAAAAAAAAA", params)
      assert String.starts_with?(casted, "t_")
      assert casted == "t_0000000000000000"
    end
  end

  describe "to_format!/4" do
    test "raises on invalid input" do
      assert_raise ArgumentError, ~r/value could not be parsed/, fn ->
        Once.to_format!("invalid", :signed, prefix: "t_")
      end
    end

    test "raises on wrong prefix" do
      assert_raise ArgumentError, ~r/value could not be parsed/, fn ->
        Once.to_format!("wrong_AAAAAAAAAAA", :signed, prefix: "t_")
      end
    end

    test "raises on unprefixed value" do
      assert_raise ArgumentError, ~r/value could not be parsed/, fn ->
        Once.to_format!("AAAAAAAAAAA", :signed, prefix: "t_")
      end
    end

    test "successfully converts valid prefixed values" do
      assert "t_0000000000000000" = Once.to_format!("t_AAAAAAAAAAA", :hex, prefix: "t_")
    end
  end

  describe "load with corrupt data" do
    test "rejects corrupt prefixed data when persist_prefix is true" do
      params = %{@base_opts | persist_prefix: true, db_format: :url64}

      # Invalid url64 after prefix
      assert :error = Once.load("t_!!invalid!!", nil, params)

      # Truncated data after prefix
      assert :error = Once.load("t_AA", nil, params)
    end

    test "rejects data with wrong prefix when persist_prefix is true" do
      params = %{@base_opts | persist_prefix: true, db_format: :url64}

      assert :error = Once.load("wrong_AAAAAAAAAAA", nil, params)
    end

    test "rejects unprefixed data when persist_prefix is true" do
      params = %{@base_opts | persist_prefix: true, db_format: :url64}

      assert :error = Once.load("AAAAAAAAAAA", nil, params)
    end
  end
end
