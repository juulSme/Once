defimpl String.Chars, for: Once.Query.Boundary do
  def to_string(boundary) do
    timestamp =
      case DateTime.from_unix(boundary.unix_ms, :millisecond) do
        {:ok, datetime} ->
          DateTime.to_iso8601(datetime)

        {:error, :invalid_unix_time} ->
          "#{boundary.unix_ms} milliseconds since the Unix epoch (outside DateTime range)"
      end

    "#{readable_bound(boundary.bound)} id of #{timestamp}"
  end

  defp readable_bound(:lower), do: "first"
  defp readable_bound(:upper), do: "last"
end
