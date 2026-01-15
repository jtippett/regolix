defmodule Regolix.Native do
  use Rustler, otp_app: :regolix, crate: "regolix"

  @spec native_new() :: reference()
  def native_new(), do: :erlang.nif_error(:nif_not_loaded)
end
