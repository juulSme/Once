defmodule Once do
  @format_docs """
  - `:encoded` a url64-encoded string of 11 characters, for example `"AAjhfZyAAAE"`
  - `:raw` a bitstring of 64 bits, for example `<<0, 8, 225, 125, 156, 128, 0, 2>>`
  - `:signed` a signed 64-bits integer, like `-12345`, between -(2^63) and 2^63-1
  - `:unsigned` an unsigned 64-bits integer, like `67890`, between 0 and 2^64-1
  """
  @options_docs """
  - `:no_noncense` name of the NoNoncense instance used to generate new IDs (default `Once`)
  - `:ex_format` what an ID looks like in Elixir, one of `t:format/0` (default `:encoded`)
  - `:db_format` what an ID looks like in your database, one of `t:format/0` (default `:signed`)
  - `:encrypt?` enable for encrypted nonces (default `false`)
  - `:get_key` a zero-arity getter for the 192-bits encryption key, required if encryption is enabled
  """

  @moduledoc """
  Once is an Ecto type for locally unique 64-bits IDs generated by multiple Elixir nodes. Locally unique IDs make it easier to keep things separated, simplify caching and simplify inserting related things (because you don't have to wait for the database to return the ID).

  A Once can look however you want, and can be stored in multiple ways as well. By default, in Elixir it's a url64-encoded 11-char string, and in the database it's a signed bigint. By using the `:ex_format` and `:db_format` options, you can choose both the Elixir and storage format out of `t:format/0`. You can pick any combination and use `to_format/2` to transform them as you wish!

  Because a Once fits into an SQL bigint, they use little space and keep indexes small and fast. Because of their [structure](https://hexdocs.pm/no_noncense/NoNoncense.html#module-how-it-works) they have counter-like data locality, which helps your indexes perform well, [unlike UUIDv4s](https://www.cybertec-postgresql.com/en/unexpected-downsides-of-uuid-keys-in-postgresql/). If you don't care about that and want unpredictable IDs, you can use encrypted IDs that seem random and are still unique.

  The actual values are generated by `NoNoncense`, which performs incredibly well, hitting rates of tens of millions of nonces per second, and it also helps you to safeguard the uniqueness guarantees.

  The library has only `Ecto` and its sibling `NoNoncense` as dependencies.

  ## Usage

  To get going, you need to set up a `NoNoncense` instance to generate the base unique values. Follow [its documentation](https://hexdocs.pm/no_noncense) to do so. `Once` expects an instance with its own module name by default, like so:

      # application.ex (read the NoNoncense docs!)
      machine_id = NoNoncense.MachineId.id!(opts)
      NoNoncense.init(name: Once, machine_id: machine_id)

  In your `Ecto` schemas, you can then use the type:

      schema "things" do
        field :id, Once
      end

  And that's it!

  ## Options

  The Ecto type takes a few optional parameters:

  #{@options_docs}

  ## Data formats

  There's a drawback to having different data formats for Elixir and SQL: it makes it harder to compare the two. The following are all the same ID:

      -1
      <<255, 255, 255, 255, 255, 255, 255, 255>>
      "__________8"
      18_446_744_073_709_551_615

  If you use the defaults `:encoded` as the Elixir format and `:signed` in your database, you could see `"AAAAAACYloA"` in Elixir and `10_000_000` in your database. The reasoning behind these defaults is that the encoded format is readable, short, and JSON safe by default, while the signed format means you can use a standard bigint column type.

  The negative integers will not cause problems with Postgres and MySQL, they both happily swallow them. Also, negative integers will only start to appear after ~70 years of usage.

  If you don't like the formats, it's really easy to change them! The Elixir format especially, which can be changed at any time. Be mindful of JSON limitations if you use integers.

  The supported formats are:

  #{@format_docs}

  ## On local uniqueness

  By locally unique, we mean unique within your domain or application. UUIDs are globally unique across domains, servers and applications. A Once is not, because 64 bits is not enough to achieve that. It is enough for local uniqueness however: you can generate 8 million IDs per second on 512 machines in parallel for 140 years straight before you run out of bits, by which time your grand-grandchildren will deal with the problem. Even higher burst rates are possible and you can use separate `NoNoncense` instanses for every table if you wish.

  ## Encrypted IDs

  By default, IDs are generated using a machine init timestamp, machine ID and counter (although they should be considered to be opague). This means they leak a little information and are somewhat predictable. If you don't like that, you can use encrypted IDs by passing options `encrypt?: true` and `get_key: fn -> <<_::192>> end`. Note that encrypted IDs will cost you the data locality and decrease index performance a little. The encryption algorithm is 3DES and that can't be changed. If you want to know why, take a look at [NoNoncense](https://hexdocs.pm/no_noncense/NoNoncense.html#module-encrypted-nonces).
  """
  use Ecto.ParameterizedType

  @typedoc """
  Formats in which a `Once` can be rendered.
  They are all equivalent and can be transformed to one another.

  #{@format_docs}
  """
  @type format :: :encoded | :raw | :signed | :unsigned

  @typedoc """
  Options to initialize `Once`.

  #{@options_docs}
  """
  @type opts :: [
          no_noncense: module(),
          ex_format: format(),
          db_format: format(),
          encrypt?: boolean(),
          get_key: (-> <<_::24>>)
        ]

  @default_opts %{
    no_noncense: __MODULE__,
    encrypt?: false,
    ex_format: :encoded,
    db_format: :signed
  }

  @int_formats [:signed, :unsigned]

  #######################
  # Type implementation #
  #######################

  @impl true
  def type(%{ex_format: :raw}), do: :binary
  def type(%{ex_format: :encoded}), do: :string
  def type(%{ex_format: int}) when int in @int_formats, do: :integer

  @impl true
  @spec init(opts()) :: map()
  def init(opts \\ []) do
    opts
    |> Map.new()
    |> Enum.into(@default_opts)
    |> case do
      params = %{encrypt?: true, get_key: _} -> params
      %{encrypt?: true} -> raise ArgumentError, "you must provide :get_key"
      params -> params
    end
  end

  @impl true
  def cast(nil, _), do: {:ok, nil}
  def cast(value, params), do: to_format(value, params.ex_format)

  @impl true
  def load(nil, _, _), do: {:ok, nil}
  def load(value, _, params), do: to_format(value, params.ex_format)

  @impl true
  def dump(nil, _, _), do: {:ok, nil}
  def dump(value, _, params), do: to_format(value, params.db_format)

  @impl true
  def autogenerate(params = %{encrypt?: false}) do
    NoNoncense.nonce(params.no_noncense, 64)
    |> to_format!(params.ex_format)
  end

  def autogenerate(params) do
    NoNoncense.encrypted_nonce(params.no_noncense, 64, params.get_key.())
    |> to_format!(params.ex_format)
  end

  #####################
  # Mapping functions #
  #####################

  @doc """
  Transform the different forms that a `Once` can take to one another.
  The formats can be found in `t:format/0`.

      iex> Once.to_format("4BCDEFghijk", :raw)
      {:ok, <<224, 16, 131, 16, 88, 33, 138, 57>>}
      iex> Once.to_format(<<224, 16, 131, 16, 88, 33, 138, 57>>, :signed)
      {:ok, -2301195303365014983}
      iex> Once.to_format(-2301195303365014983, :unsigned)
      {:ok, 16145548770344536633}
      iex> Once.to_format(16145548770344536633, :encoded)
      {:ok, "4BCDEFghijk"}

      iex> Once.to_format(-1, :encoded)
      {:ok, "__________8"}
      iex> Once.to_format("__________8", :raw)
      {:ok, <<255, 255, 255, 255, 255, 255, 255, 255>>}
      iex> Once.to_format(<<255, 255, 255, 255, 255, 255, 255, 255>>, :unsigned)
      {:ok, 18446744073709551615}
      iex> Once.to_format(18446744073709551615, :signed)
      {:ok, -1}

      iex> Once.to_format(Integer.pow(2, 64), :unsigned)
      :error
  """
  @spec to_format(binary() | integer(), format()) :: {:ok, binary() | integer()} | :error
  def to_format(value, format)
  # to :encoded
  def to_format(encoded = <<_::88>>, :encoded), do: {:ok, encoded}
  def to_format(raw = <<_::64>>, :encoded), do: encode(raw)

  def to_format(int, :encoded) when is_integer(int) do
    convert_int(int, :signed) |> if_ok(&encode(<<&1::signed-64>>))
  end

  # to :raw
  def to_format(encoded = <<_::88>>, :raw), do: decode(encoded)
  def to_format(raw = <<_::64>>, :raw), do: {:ok, raw}

  def to_format(int, :raw) when is_integer(int) do
    convert_int(int, :signed) |> if_ok(&{:ok, <<&1::signed-64>>})
  end

  # to :signed / :unsigned
  def to_format(encoded = <<_::88>>, int_format) when int_format in @int_formats do
    decode(encoded) |> if_ok(&to_format(&1, int_format))
  end

  def to_format(_raw = <<int::signed-64>>, :signed), do: {:ok, int}
  def to_format(_raw = <<int::unsigned-64>>, :unsigned), do: {:ok, int}

  def to_format(int, int_format) when is_integer(int) and int_format in @int_formats do
    convert_int(int, int_format)
  end

  def to_format(_, _), do: :error

  @doc """
  Same as `to_format/2` but raises on error.

      iex> -200
      ...> |> Once.to_format!(:encoded)
      ...> |> Once.to_format!(:raw)
      ...> |> Once.to_format!(:unsigned)
      ...> |> Once.to_format!(:signed)
      -200

      iex> Once.to_format!(Integer.pow(2, 64), :unsigned)
      ** (ArgumentError) value could not be parsed
  """
  @spec to_format!(binary() | integer(), format()) :: binary() | integer()
  def to_format!(value, format) do
    case to_format(value, format) do
      {:ok, value} -> value
      _ -> raise ArgumentError, "value could not be parsed"
    end
  end

  ###########
  # Private #
  ###########

  @range Integer.pow(2, 64)
  @signed_min -Integer.pow(2, 63)
  @signed_max Integer.pow(2, 63) - 1
  @unsigned_max @range - 1

  defp convert_int(int, format)
  defp convert_int(int, _) when int < @signed_min, do: :error
  defp convert_int(int, _) when int > @unsigned_max, do: :error

  defp convert_int(int, :signed) when int > @signed_max, do: {:ok, int - @range}
  defp convert_int(int, :unsigned) when int < 0, do: {:ok, int + @range}

  defp convert_int(int, _), do: {:ok, int}

  defp if_ok({:ok, value}, then), do: then.(value)
  defp if_ok(other, _), do: other

  defp encode(value), do: {:ok, Base.url_encode64(value, padding: false)}
  defp decode(value), do: Base.url_decode64(value, padding: false)
end
