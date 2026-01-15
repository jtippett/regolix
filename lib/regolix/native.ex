defmodule Regolix.Native do
  use Rustler, otp_app: :regolix, crate: "regolix"

  @spec native_new() :: reference()
  def native_new(), do: :erlang.nif_error(:nif_not_loaded)

  @spec native_add_policy(reference(), String.t(), String.t()) ::
          {:ok, {}} | {:error, {atom(), String.t()}}
  def native_add_policy(_engine, _name, _source), do: :erlang.nif_error(:nif_not_loaded)
end
