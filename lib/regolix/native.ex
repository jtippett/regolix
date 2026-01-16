defmodule Regolix.Native do
  use Rustler, otp_app: :regolix, crate: "regolix"

  @spec native_new() :: reference()
  def native_new(), do: :erlang.nif_error(:nif_not_loaded)

  @spec native_add_policy(reference(), String.t(), String.t()) ::
          {:ok, {}} | {:error, {atom(), String.t()}}
  def native_add_policy(_engine, _name, _source), do: :erlang.nif_error(:nif_not_loaded)

  @spec native_set_input(reference(), String.t()) :: :ok | {:error, {atom(), String.t()}}
  def native_set_input(_engine, _json_input), do: :erlang.nif_error(:nif_not_loaded)

  @spec native_get_packages(reference()) :: {:ok, [String.t()]} | {:error, {atom(), String.t()}}
  def native_get_packages(_engine), do: :erlang.nif_error(:nif_not_loaded)

  @spec native_add_data(reference(), String.t()) :: {:ok, {}} | {:error, {atom(), String.t()}}
  def native_add_data(_engine, _json), do: :erlang.nif_error(:nif_not_loaded)

  @spec native_eval_query(reference(), String.t()) :: term() | {:error, {atom(), String.t()}}
  def native_eval_query(_engine, _query), do: :erlang.nif_error(:nif_not_loaded)

  @spec native_clear_data(reference()) :: {:ok, {}} | {:error, {atom(), String.t()}}
  def native_clear_data(_engine), do: :erlang.nif_error(:nif_not_loaded)

  @spec native_enable_coverage(reference(), boolean()) :: {:ok, {}} | {:error, {atom(), String.t()}}
  def native_enable_coverage(_engine, _enable), do: :erlang.nif_error(:nif_not_loaded)

  @spec native_get_coverage_report(reference()) :: {:ok, map()} | {:error, {atom(), String.t()}}
  def native_get_coverage_report(_engine), do: :erlang.nif_error(:nif_not_loaded)

  @spec native_clear_coverage(reference()) :: {:ok, {}} | {:error, {atom(), String.t()}}
  def native_clear_coverage(_engine), do: :erlang.nif_error(:nif_not_loaded)
end
