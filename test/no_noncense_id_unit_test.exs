defmodule NoNoncenseIDUnitTest do
  use ExUnit.Case, async: true
  doctest NoNoncenseID

  @range Integer.pow(2, 64)
  @signed_min -Integer.pow(2, 63)
  @signed_max Integer.pow(2, 63) - 1
  @unsigned_max @range - 1

  describe "to_format/2" do
    @format_tests [
      %{encoded: "AAAAAAAAAAA", raw: <<0, 0, 0, 0, 0, 0, 0, 0>>, signed: 0, unsigned: 0},
      %{
        encoded: "__________8",
        raw: <<255, 255, 255, 255, 255, 255, 255, 255>>,
        signed: -1,
        unsigned: @unsigned_max
      },
      %{
        encoded: "f_________8",
        raw: <<127, 255, 255, 255, 255, 255, 255, 255>>,
        signed: @signed_max,
        unsigned: @signed_max
      },
      %{
        encoded: "gAAAAAAAAAA",
        raw: <<128, 0, 0, 0, 0, 0, 0, 0>>,
        signed: @signed_min,
        unsigned: @signed_max + 1
      },
      # out of bounds
      %{invalid: @range, encoded: :error, raw: :error, signed: :error, unsigned: :error},
      %{invalid: @signed_min - 1, encoded: :error, raw: :error, signed: :error, unsigned: :error}
    ]

    for formats_values <- @format_tests,
        {format_in, input} <- formats_values,
        {format_out, output} <- formats_values,
        input != :error and format_in != :invalid do
      test "should map [#{format_in}: #{inspect(input)}] to [#{format_out}: #{inspect(output)}]" do
        case NoNoncenseID.to_format(unquote(input), unquote(format_out)) do
          {:ok, result} -> result
          result -> result
        end
        |> then(fn res -> assert unquote(output) == res end)
      end
    end
  end

  describe "init/1" do
    test "requires get_key if :encrypt? == true" do
      assert_raise ArgumentError, "you must provide :get_key", fn ->
        NoNoncenseID.init(encrypt?: true)
      end
    end

    test "sets defaults" do
      assert %{
               db_format: :signed,
               encrypt?: false,
               ex_format: :encoded,
               no_noncense: NoNoncenseID
             } == NoNoncenseID.init()
    end

    test "overrides defaults" do
      assert %{db_format: :encoded, ex_format: :signed} =
               NoNoncenseID.init(db_format: :encoded, ex_format: :signed)
    end
  end

  test "cast/dump/load accept nil value" do
    assert {:ok, nil} = NoNoncenseID.cast(nil, %{})
    assert {:ok, nil} = NoNoncenseID.dump(nil, %{}, %{})
    assert {:ok, nil} = NoNoncenseID.load(nil, %{}, %{})
  end

  describe "autogenerate/1" do
    test "generates plaintext nonces in configured format" do
      params = %{encrypt?: false, no_noncense: NoNoncenseID}

      assert <<_::64>> = Map.put(params, :ex_format, :raw) |> NoNoncenseID.autogenerate()
      assert <<_::88>> = Map.put(params, :ex_format, :encoded) |> NoNoncenseID.autogenerate()
      int = Map.put(params, :ex_format, :signed) |> NoNoncenseID.autogenerate()
      assert is_integer(int)
    end

    test "generates plaintext nonces" do
      params = %{encrypt?: false, no_noncense: NoNoncenseID, ex_format: :raw}

      assert <<prefix1::42, _::bits>> = NoNoncenseID.autogenerate(params)
      assert <<prefix2::42, _::bits>> = NoNoncenseID.autogenerate(params)
      assert prefix1 == prefix2
    end

    test "generates encrypted nonces in configured format" do
      params = %{
        encrypt?: true,
        no_noncense: NoNoncenseID,
        get_key: fn -> :crypto.strong_rand_bytes(24) end
      }

      assert <<_::64>> = Map.put(params, :ex_format, :raw) |> NoNoncenseID.autogenerate()
      assert <<_::88>> = Map.put(params, :ex_format, :encoded) |> NoNoncenseID.autogenerate()
      int = Map.put(params, :ex_format, :signed) |> NoNoncenseID.autogenerate()
      assert is_integer(int)
    end

    test "generates encrypted nonces" do
      params = %{
        encrypt?: true,
        no_noncense: NoNoncenseID,
        get_key: fn -> :crypto.strong_rand_bytes(24) end,
        ex_format: :raw
      }

      assert <<prefix1::42, _::bits>> = NoNoncenseID.autogenerate(params)
      assert <<prefix2::42, _::bits>> = NoNoncenseID.autogenerate(params)
      assert prefix1 != prefix2
    end
  end
end
