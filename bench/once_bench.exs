Mix.Task.run("app.start")

base_key =
  <<93, 198, 179, 97, 145, 106, 54, 165, 219, 77, 223, 54, 58, 16, 164, 222, 242, 214, 181, 143,
    10, 19, 20, 51, 63, 238, 38, 150, 45, 183, 153, 69>>

NoNoncense.init(name: Once.Bench.Counter, machine_id: 1, base_key: base_key)
NoNoncense.init(name: Once.Bench.Sortable, machine_id: 2, base_key: base_key)
NoNoncense.init(name: Once.Bench.Encrypted, machine_id: 3, base_key: base_key)
NoNoncense.init(name: Once.Bench.Masked, machine_id: 4, base_key: base_key)

counter_params = Once.init(no_noncense: Once.Bench.Counter, nonce_type: :counter, ex_format: :url64)
sortable_params = Once.init(no_noncense: Once.Bench.Sortable, nonce_type: :sortable, ex_format: :url64)
encrypted_params = Once.init(no_noncense: Once.Bench.Encrypted, nonce_type: :encrypted, ex_format: :url64)
masked_params = Once.init(no_noncense: Once.Bench.Masked, nonce_type: :counter, ex_format: :url64, mask: true)

sample = Once.autogenerate(counter_params)

if Code.ensure_loaded?(Benchee) do
  apply(Benchee, :run, [
    %{
      "autogenerate counter" => fn -> Once.autogenerate(counter_params) end,
      "autogenerate sortable" => fn -> Once.autogenerate(sortable_params) end,
      "autogenerate encrypted" => fn -> Once.autogenerate(encrypted_params) end,
      "autogenerate masked" => fn -> Once.autogenerate(masked_params) end,
      "to_format url64 -> raw" => fn -> Once.to_format!(sample, :raw) end,
      "to_format url64 -> hex32" => fn -> Once.to_format!(sample, :hex32) end
    },
    [time: 5, memory_time: 1]
  ])
else
  IO.puts("Benchee is unavailable. Run benchmarks with mix bench")
end
