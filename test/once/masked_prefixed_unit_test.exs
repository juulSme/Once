defmodule Once.MaskedPrefixedUnitTest do
  use ExUnit.Case, async: true
  use Once.Constants
  alias Once.Encode

  @base_opts Once.init(prefix: "t_", mask: true)

  defp decrypt(value), do: NoNoncense.decrypt(Once, value)

  describe "autogenerate/1" do
    test "generates prefixed masked IDs in configured format" do
      assert <<"t_", _::64>> = %{@base_opts | ex_format: :raw} |> Once.autogenerate()
      assert <<"t_", _::88>> = %{@base_opts | ex_format: :url64} |> Once.autogenerate()
      assert <<"t_", int::binary>> = %{@base_opts | ex_format: :signed} |> Once.autogenerate()
      assert String.to_integer(int) |> to_string() == int
    end

    test "generates counter nonces with prefix and mask" do
      params = %{@base_opts | nonce_type: :counter, ex_format: :raw}

      assert <<"t_", masked1::64>> = Once.autogenerate(params)
      assert <<"t_", masked2::64>> = Once.autogenerate(params)

      # Decrypt and verify structure
      <<prefix1::42, _::9, c1::13>> = decrypt(<<masked1::64>>)
      <<prefix2::42, _::9, c2::13>> = decrypt(<<masked2::64>>)
      assert prefix1 == prefix2
      assert c2 > c1
    end

    test "generates sortable nonces with prefix and mask" do
      params = %{@base_opts | nonce_type: :sortable, ex_format: :raw}

      assert <<"t_", masked1::64>> = Once.autogenerate(params)
      Process.sleep(5)
      assert <<"t_", masked2::64>> = Once.autogenerate(params)

      # Decrypt and verify timestamps differ
      <<ts1::42, _::9, 0::13>> = decrypt(<<masked1::64>>)
      <<ts2::42, _::9, 0::13>> = decrypt(<<masked2::64>>)
      assert ts1 < ts2
    end
  end

  describe "cast/2" do
    test "accepts prefixed masked IDs" do
      params = %{@base_opts | ex_format: :hex}
      generated = Once.autogenerate(params)

      assert {:ok, ^generated} = Once.cast(generated, params)
    end

    test "accepts various formats with prefix and mask" do
      # Generate a value
      params = %{@base_opts | ex_format: :raw}
      <<"t_", raw::64>> = Once.autogenerate(params)

      # Cast raw format
      assert {:ok, <<"t_", ^raw::64>>} = Once.cast(<<"t_", raw::64>>, params)

      # Cast url64 format
      raw_url64 = Encode.encode64(<<raw::64>>)

      assert {:ok, <<"t_", ^raw::64>>} =
               Once.cast("t_#{raw_url64}", %{params | ex_format: :raw})
    end

    test "rejects unprefixed masked values" do
      params = %{@base_opts | ex_format: :url64}
      assert :error = Once.cast("AAAAAAAAAAA", params)
    end

    test "rejects wrong prefix" do
      params = %{@base_opts | ex_format: :url64}
      assert :error = Once.cast("wrong_AAAAAAAAAAA", params)
      assert :error = Once.cast("usr_AAAAAAAAAAA", %{params | prefix: "prod_"})
    end
  end

  describe "dump/3" do
    test "strips prefix and unmasks by default" do
      params = %{@base_opts | ex_format: :url64, db_format: :signed}
      masked_prefixed = Once.autogenerate(params)

      # Extract the masked part without prefix
      <<"t_", masked_part::binary>> = masked_prefixed
      {:ok, decoded} = masked_part |> Encode.decode64()

      # Decrypt to get plaintext
      plaintext = decrypt(decoded)

      # Dump should strip prefix and unmask
      {:ok, db_value} = Once.dump(masked_prefixed, nil, params)
      assert plaintext == <<db_value::signed-64>>
      assert is_integer(db_value)
    end

    test "accepts various input formats with prefix and mask" do
      params = %{@base_opts | ex_format: :url64, db_format: :raw}

      # Generate and dump
      generated = Once.autogenerate(params)
      {:ok, dumped} = Once.dump(generated, nil, params)

      # Should be raw binary without prefix
      assert <<_::64>> = dumped
      refute String.starts_with?(dumped, "t_")
    end

    test "unmasks correctly for different db_formats" do
      base = %{@base_opts | ex_format: :url64}

      # Generate a masked ID
      id = Once.autogenerate(base)

      # Dump to different formats
      {:ok, raw} = Once.dump(id, nil, %{base | db_format: :raw})
      {:ok, signed} = Once.dump(id, nil, %{base | db_format: :signed})
      {:ok, unsigned} = Once.dump(id, nil, %{base | db_format: :unsigned})
      {:ok, hex} = Once.dump(id, nil, %{base | db_format: :hex})

      # All should be unmasked and equivalent
      assert <<signed::signed-64>> == raw
      assert <<unsigned::unsigned-64>> == raw
      assert hex == Encode.encode16(raw)
    end
  end

  describe "load/3" do
    test "loads unmasked value and re-encrypts with prefix" do
      params = %{@base_opts | ex_format: :url64, db_format: :signed}

      # Start with plaintext integer from database
      plaintext_int = 12_345_678

      # Load should encrypt and add prefix
      {:ok, loaded} = Once.load(plaintext_int, nil, params)
      assert <<"t_", encrypted_part::binary>> = loaded

      # Decrypt to verify
      {:ok, decoded} = encrypted_part |> Encode.decode64()
      assert <<^plaintext_int::signed-64>> = decrypt(decoded)
    end

    test "handles different input formats" do
      params = %{@base_opts | ex_format: :url64, db_format: :raw}

      # Create plaintext
      plaintext = <<12, 34, 56, 78, 90, 12, 34, 56>>

      # Load from raw binary
      {:ok, loaded} = Once.load(plaintext, nil, params)
      assert <<"t_", _::88>> = loaded

      # Verify encryption
      <<"t_", encrypted::binary>> = loaded
      {:ok, decoded} = encrypted |> Encode.decode64()
      assert plaintext == decrypt(decoded)
    end
  end

  describe "round-trip" do
    test "autogenerate → dump → load maintains plaintext" do
      params = %{@base_opts | ex_format: :url64, db_format: :signed}

      # Generate prefixed masked ID
      masked_prefixed = Once.autogenerate(params)
      assert <<"t_", _::88>> = masked_prefixed

      # Extract and decrypt to get plaintext
      <<"t_", masked_part::binary>> = masked_prefixed
      {:ok, decoded} = masked_part |> Encode.decode64()
      plaintext = decrypt(decoded)

      # Dump (unmask and strip prefix)
      {:ok, db_value} = Once.dump(masked_prefixed, nil, params)
      assert plaintext == <<db_value::signed-64>>

      # Load (encrypt and add prefix)
      {:ok, reloaded} = Once.load(db_value, nil, params)
      assert ^masked_prefixed = reloaded
    end

    test "round-trip with raw format" do
      params = %{@base_opts | ex_format: :hex32, db_format: :raw}

      generated = Once.autogenerate(params)
      {:ok, dumped} = Once.dump(generated, nil, params)
      {:ok, loaded} = Once.load(dumped, nil, params)

      assert generated == loaded
    end

    test "round-trip with hex format" do
      params = %{@base_opts | ex_format: :hex, db_format: :unsigned}

      generated = Once.autogenerate(params)
      {:ok, dumped} = Once.dump(generated, nil, params)
      {:ok, loaded} = Once.load(dumped, nil, params)

      assert generated == loaded
    end

    test "round-trip with hex32 format" do
      params = %{@base_opts | ex_format: :hex32, db_format: :signed}

      generated = Once.autogenerate(params)
      {:ok, dumped} = Once.dump(generated, nil, params)
      {:ok, loaded} = Once.load(dumped, nil, params)

      assert generated == loaded
    end
  end

  describe "persist_prefix with mask" do
    test "dump preserves prefix but decrypts value" do
      params = %{@base_opts | persist_prefix: true, db_format: :url64, ex_format: :url64}
      generated = Once.autogenerate(params)

      {:ok, dumped} = Once.dump(generated, nil, params)

      # Should have prefix but be decrypted (plaintext)
      assert <<"t_", _::88>> = dumped

      # Verify the dumped value is NOT the same as generated (because it's decrypted)
      assert dumped != generated

      # Verify by decrypting generated and comparing
      <<"t_", gen_part::binary>> = generated
      <<"t_", dump_part::binary>> = dumped
      {:ok, gen_decoded} = gen_part |> Encode.decode64()
      plaintext = decrypt(gen_decoded)
      {:ok, dump_decoded} = dump_part |> Encode.decode64()
      assert plaintext == dump_decoded
    end

    test "load accepts prefixed plaintext value when persist_prefix is true" do
      params = %{@base_opts | persist_prefix: true, db_format: :url64, ex_format: :url64}
      generated = Once.autogenerate(params)

      {:ok, dumped} = Once.dump(generated, nil, params)

      # Dumped value should be plaintext (not encrypted) but prefixed
      <<"t_", dumped_part::binary>> = dumped
      {:ok, plaintext_decoded} = dumped_part |> Encode.decode64()

      # This plaintext can be loaded and will be encrypted
      {:ok, loaded} = Once.load(dumped, nil, params)

      assert loaded == generated
      assert <<"t_", _::88>> = loaded

      # Verify loaded is encrypted by decrypting it
      <<"t_", loaded_part::binary>> = loaded
      {:ok, loaded_decoded} = loaded_part |> Encode.decode64()
      assert plaintext_decoded == decrypt(loaded_decoded)
    end

    test "load rejects unprefixed value when persist_prefix is true" do
      params = %{@base_opts | persist_prefix: true, db_format: :url64}
      assert :error = Once.load("AAAAAAAAAAA", nil, params)
    end

    test "round-trip with persist_prefix true for raw format" do
      params = %{@base_opts | persist_prefix: true, db_format: :raw, ex_format: :raw}
      generated = Once.autogenerate(params)

      {:ok, dumped} = Once.dump(generated, nil, params)
      {:ok, loaded} = Once.load(dumped, nil, params)

      assert loaded == generated
      assert <<"t_", _::64>> = loaded
    end

    test "round-trip with persist_prefix true for hex format" do
      params = %{@base_opts | persist_prefix: true, db_format: :hex, ex_format: :hex}
      generated = Once.autogenerate(params)

      {:ok, dumped} = Once.dump(generated, nil, params)
      {:ok, loaded} = Once.load(dumped, nil, params)

      assert loaded == generated
      assert <<"t_", _::128>> = loaded
    end
  end

  describe "prefix outside encryption verification" do
    test "prefix can be changed during dump/load" do
      params1 = %{@base_opts | prefix: "old_", ex_format: :url64, db_format: :signed}
      params2 = %{@base_opts | prefix: "new_", ex_format: :url64, db_format: :signed}

      # Generate with old prefix
      old_id = Once.autogenerate(params1)
      assert <<"old_", _::88>> = old_id

      # Dump strips prefix
      {:ok, db_value} = Once.dump(old_id, nil, params1)

      # Load with new prefix
      {:ok, new_id} = Once.load(db_value, nil, params2)
      assert <<"new_", _::88>> = new_id

      # The unmasked values should be identical
      <<"old_", old_masked::binary>> = old_id
      <<"new_", new_masked::binary>> = new_id

      {:ok, old_decoded} = old_masked |> Encode.decode64()
      {:ok, new_decoded} = new_masked |> Encode.decode64()

      assert decrypt(old_decoded) == decrypt(new_decoded)
    end

    test "prefix not included in encrypted portion" do
      params = %{@base_opts | ex_format: :raw}

      # Generate ID with prefix
      <<"t_", masked::64>> = Once.autogenerate(params)

      # Decrypt just the masked part (without prefix)
      plaintext = decrypt(<<masked::64>>)
      assert <<_::64>> = plaintext

      # The plaintext should not contain the prefix
      refute String.contains?(plaintext, "t_")
    end
  end

  describe "format conversion with prefix and mask" do
    test "converts between formats while preserving prefix" do
      params = %{@base_opts | ex_format: :url64}
      generated = Once.autogenerate(params)

      # Convert to hex
      assert {:ok, <<"t_", _::128>>} = Once.cast(generated, %{params | ex_format: :hex})

      # Convert to hex32
      assert {:ok, <<"t_", _::104>>} = Once.cast(generated, %{params | ex_format: :hex32})

      # Convert to raw
      assert {:ok, <<"t_", _::64>>} = Once.cast(generated, %{params | ex_format: :raw})
    end

    test "format conversion preserves encryption" do
      params = %{@base_opts | ex_format: :url64}
      <<"t_", url64_part::binary>> = Once.autogenerate(params)

      # Get the plaintext
      {:ok, decoded} = url64_part |> Encode.decode64()
      plaintext = decrypt(decoded)

      # Convert to different format
      {:ok, hex_id} = Once.cast("t_#{url64_part}", %{params | ex_format: :hex})
      <<"t_", hex_part::binary>> = hex_id

      # Verify same plaintext
      {:ok, hex_decoded} = Encode.decode16(hex_part)
      assert plaintext == decrypt(hex_decoded)
    end
  end
end
