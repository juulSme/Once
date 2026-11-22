defimpl Inspect, for: Once.Query.Boundary do
  import Inspect.Algebra

  if function_exported?(Inspect.Algebra, :to_doc_with_opts, 2) do
    def inspect(boundary, opts) do
      {timestamp, opts} = boundary.unix_ms |> readable_time() |> to_doc_with_opts(opts)

      {boundary_doc(timestamp, boundary.bound), opts}
    end
  else
    def inspect(boundary, opts) do
      boundary.unix_ms |> readable_time() |> to_doc(opts) |> boundary_doc(boundary.bound)
    end
  end

  defp boundary_doc(timestamp, bound) do
    concat(["#Once.Query.Boundary<", readable_bound(bound), " id of ", timestamp, ">"])
  end

  defp readable_time(unix_ms) do
    case DateTime.from_unix(unix_ms, :millisecond) do
      {:ok, datetime} -> datetime
      {:error, :invalid_unix_time} -> {:unix_ms, unix_ms}
    end
  end

  defp readable_bound(:lower), do: "first"
  defp readable_bound(:upper), do: "last"
end
