defmodule Regolix do
  @moduledoc """
  Elixir wrapper for the Regorus Rego policy engine.
  """

  alias Regolix.Native

  @type engine :: reference()
  @type json_encodable :: map() | list() | String.t() | number() | boolean() | nil
  @type eval_result :: json_encodable() | :undefined

  @doc """
  Creates a new Rego policy engine.

  ## Examples

      {:ok, engine} = Regolix.new()
  """
  @spec new() :: {:ok, engine()}
  def new do
    {:ok, Native.native_new()}
  end

  @doc """
  Creates a new Rego policy engine. Raises on error.
  """
  @spec new!() :: engine()
  def new! do
    Native.native_new()
  end
end
