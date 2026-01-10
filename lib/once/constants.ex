defmodule Once.Constants do
  @moduledoc false

  defmacro __using__(_opts \\ []) do
    quote do
      @bigint_size Integer.pow(2, 64)
      @signed_min -Integer.pow(2, 63)
      @signed_max Integer.pow(2, 63) - 1
      @unsigned_min 0
      @unsigned_max @bigint_size - 1

      @int_formats [:signed, :unsigned]
      @encoded_formats [:url64, :hex, :hex32]
      @binary_formats @encoded_formats ++ [:raw]
      @formats @int_formats ++ @binary_formats
    end
  end
end
