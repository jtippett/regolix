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
      {:error, {type, message}} ->
        {:error, %Error{type: type, message: message}}

      {:error, %Jason.EncodeError{} = e} ->
        {:error, %Error{type: :json_error, message: Exception.message(e)}}

      {:error, %Protocol.UndefinedError{} = e} ->
        {:error, %Error{type: :json_error, message: Exception.message(e)}}
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

  @doc """
  Adds data to the engine's data document.

  Can be called multiple times to merge data.

  ## Examples

      {:ok, engine} = Regolix.add_data(engine, %{"users" => %{"alice" => %{"role" => "admin"}}})
  """
  @spec add_data(engine(), json_encodable()) :: {:ok, engine()} | {:error, Error.t()}
  def add_data(engine, data) do
    with {:ok, json} <- encode_json(data),
         {:ok, {}} <- Native.native_add_data(engine, json) do
      {:ok, engine}
    else
      {:error, {type, message}} ->
        {:error, %Error{type: type, message: message}}

      {:error, %Jason.EncodeError{} = e} ->
        {:error, %Error{type: :json_error, message: Exception.message(e)}}

      {:error, %Protocol.UndefinedError{} = e} ->
        {:error, %Error{type: :json_error, message: Exception.message(e)}}
    end
  end

  @doc """
  Adds data to the engine. Raises on error.
  """
  @spec add_data!(engine(), json_encodable()) :: engine()
  def add_data!(engine, data) do
    case add_data(engine, data) do
      {:ok, engine} -> engine
      {:error, error} -> raise error
    end
  end

  @doc """
  Clears all data from the engine, keeping policies intact.

  ## Examples

      {:ok, engine} = Regolix.clear_data(engine)
  """
  @spec clear_data(engine()) :: {:ok, engine()} | {:error, Error.t()}
  def clear_data(engine) do
    case Native.native_clear_data(engine) do
      {:ok, {}} -> {:ok, engine}
      {:error, {type, message}} -> {:error, %Error{type: type, message: message}}
    end
  end

  @doc """
  Clears all data from the engine. Raises on error.
  """
  @spec clear_data!(engine()) :: engine()
  def clear_data!(engine) do
    case clear_data(engine) do
      {:ok, engine} -> engine
      {:error, error} -> raise error
    end
  end

  @doc """
  Evaluates a Rego query against the engine.

  Returns the result as Elixir terms, or `:undefined` if the query has no result.

  ## Examples

      {:ok, true} = Regolix.eval_query(engine, "data.authz.allow")
      {:ok, :undefined} = Regolix.eval_query(engine, "data.authz.nonexistent")
  """
  @spec eval_query(engine(), String.t()) :: {:ok, eval_result()} | {:error, Error.t()}
  def eval_query(engine, query) do
    case Native.native_eval_query(engine, query) do
      {:ok, result} -> {:ok, result}
      {:error, {type, message}} -> {:error, %Error{type: type, message: message}}
    end
  end

  @doc """
  Evaluates a Rego query. Raises on error.
  """
  @spec eval_query!(engine(), String.t()) :: eval_result()
  def eval_query!(engine, query) do
    case eval_query(engine, query) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  defp encode_json(term) do
    Jason.encode(term)
  end
end
