defmodule Once.CollisionSmokeTest do
  use ExUnit.Case, async: true

  @moduletag :smoke
  @sample_size 100_000

  @base_key <<93, 198, 179, 97, 145, 106, 54, 165, 219, 77, 223, 54, 58, 16, 164, 222, 242, 214,
               181, 143, 10, 19, 20, 51, 63, 238, 38, 150, 45, 183, 153, 69>>

  setup_all do
    NoNoncense.init(name: Once.Collision.Counter, machine_id: 10, base_key: @base_key)
    NoNoncense.init(name: Once.Collision.Sortable, machine_id: 11, base_key: @base_key)
    NoNoncense.init(name: Once.Collision.Encrypted, machine_id: 12, base_key: @base_key)
    NoNoncense.init(name: Once.Collision.Masked, machine_id: 13, base_key: @base_key)
    :ok
  end

  test "counter IDs do not collide in a smoke sample" do
    params = Once.init(no_noncense: Once.Collision.Counter, nonce_type: :counter, ex_format: :raw)
    assert_unique_ids(params, @sample_size)
  end

  test "sortable IDs do not collide in a smoke sample" do
    params = Once.init(no_noncense: Once.Collision.Sortable, nonce_type: :sortable, ex_format: :raw)
    assert_unique_ids(params, @sample_size)
  end

  test "encrypted IDs do not collide in a smoke sample" do
    params = Once.init(no_noncense: Once.Collision.Encrypted, nonce_type: :encrypted, ex_format: :raw)
    assert_unique_ids(params, @sample_size)
  end

  test "masked IDs do not collide in a smoke sample" do
    params =
      Once.init(
        no_noncense: Once.Collision.Masked,
        nonce_type: :counter,
        ex_format: :raw,
        mask: true
      )

    assert_unique_ids(params, @sample_size)
  end

  defp assert_unique_ids(params, sample_size) do
    ids = for _ <- 1..sample_size, do: Once.autogenerate(params)
    assert sample_size == ids |> MapSet.new() |> MapSet.size()
  end
end
