defmodule Regolix do
  @moduledoc """
  Elixir wrapper for the Regorus Rego policy engine.
  """

  alias Regolix.{Error, Native}

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

  @doc """
  Adds a Rego policy to the engine.

  ## Examples

      {:ok, engine} = Regolix.add_policy(engine, "authz.rego", "package authz")
  """
  @spec add_policy(engine(), String.t(), String.t()) :: {:ok, engine()} | {:error, Error.t()}
  def add_policy(engine, name, source) do
    case Native.native_add_policy(engine, name, source) do
      {:ok, {}} -> {:ok, engine}
      {:error, {type, message}} -> {:error, %Error{type: type, message: message}}
    end
  end

  @doc """
  Adds a Rego policy to the engine. Raises on error.
  """
  @spec add_policy!(engine(), String.t(), String.t()) :: engine()
  def add_policy!(engine, name, source) do
    case add_policy(engine, name, source) do
      {:ok, engine} -> engine
      {:error, error} -> raise error
    end
  end

  @doc """
  Returns the list of package names loaded in the engine.

  ## Examples

      packages = Regolix.get_packages(engine)
      # => ["data.authz", "data.rbac"]
  """
  @spec get_packages(engine()) :: [String.t()]
  def get_packages(engine) do
    case Native.native_get_packages(engine) do
      {:ok, packages} -> packages
      packages when is_list(packages) -> packages
    end
  end

  @doc """
  Sets the input document for policy evaluation.

  Accepts Elixir terms (maps, lists, etc.) which are automatically JSON-encoded.

  ## Examples

      {:ok, engine} = Regolix.set_input(engine, %{"user" => "alice"})
  """
  @spec set_input(engine(), json_encodable()) :: {:ok, engine()} | {:error, Error.t()}
  def set_input(engine, input) do
    with {:ok, json} <- encode_json(input),
         {:ok, {}} <- Native.native_set_input(engine, json) do
      {:ok, engine}
    else
      {:error, {type, message}} -> {:error, %Error{type: type, message: message}}
      {:error, %Jason.EncodeError{} = e} -> {:error, %Error{type: :json_error, message: Exception.message(e)}}
      {:error, %Protocol.UndefinedError{} = e} -> {:error, %Error{type: :json_error, message: Exception.message(e)}}
    end
  end

  @doc """
  Sets the input document. Raises on error.
  """
  @spec set_input!(engine(), json_encodable()) :: engine()
  def set_input!(engine, input) do
    case set_input(engine, input) do
      {:ok, engine} -> engine
      {:error, error} -> raise error
    end
  end

  defp encode_json(term) do
    Jason.encode(term)
  end
end
