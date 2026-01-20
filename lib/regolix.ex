defmodule Regolix do
  @moduledoc """
  Elixir wrapper for the Regorus Rego policy engine.

  ## Basic Usage

      {:ok, engine} = Regolix.new()
      {:ok, engine} = Regolix.add_policy(engine, "authz.rego", \"""
        package authz
        default allow = false
        allow if input.user == "admin"
      \""")
      {:ok, engine} = Regolix.set_input(engine, %{"user" => "admin"})
      {:ok, true} = Regolix.eval_query(engine, "data.authz.allow")

  ## Coverage Tracking

  Track which policy lines are executed during evaluation:

      {result, coverage} = Regolix.with_coverage(engine, fn e ->
        Regolix.eval_query!(e, "data.authz.allow")
      end)
      # coverage => %{"authz.rego" => %{covered: [1, 2, 5], not_covered: [9, 10]}}

  For multi-query accumulation:

      engine = Regolix.enable_coverage!(engine)
      Regolix.eval_query!(engine, "data.authz.allow")
      Regolix.eval_query!(engine, "data.rbac.check")
      coverage = Regolix.get_coverage_report!(engine)
      engine = Regolix.disable_coverage!(engine)
  """

  alias Regolix.{Error, Native}

  @type engine :: reference()
  @type json_encodable :: map() | list() | String.t() | number() | boolean() | nil
  @type eval_result :: json_encodable() | :undefined
  @type coverage_report :: %{String.t() => %{covered: [pos_integer()], not_covered: [pos_integer()]}}

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
  Enables coverage tracking on the engine.

  After enabling, all query evaluations will track which policy lines are executed.
  Use `get_coverage_report/1` to retrieve the accumulated coverage data.

  ## Examples

      engine = Regolix.enable_coverage!(engine)
  """
  @spec enable_coverage!(engine()) :: engine()
  def enable_coverage!(engine) do
    case Native.native_enable_coverage(engine, true) do
      {:ok, {}} -> engine
      {:error, {type, message}} -> raise %Error{type: type, message: message}
    end
  end

  @doc """
  Disables coverage tracking on the engine.

  Coverage data is retained until explicitly cleared with `clear_coverage!/1`.

  ## Examples

      engine = Regolix.disable_coverage!(engine)
  """
  @spec disable_coverage!(engine()) :: engine()
  def disable_coverage!(engine) do
    case Native.native_enable_coverage(engine, false) do
      {:ok, {}} -> engine
      {:error, {type, message}} -> raise %Error{type: type, message: message}
    end
  end

  @doc """
  Returns the accumulated coverage report.

  Returns coverage data for all policy files, showing which lines were
  executed (covered) and which were not (not_covered).

  ## Examples

      {:ok, coverage} = Regolix.get_coverage_report(engine)
      # => %{"authz.rego" => %{covered: [1, 2, 5], not_covered: [9, 10]}}
  """
  @spec get_coverage_report(engine()) :: {:ok, coverage_report()} | {:error, Error.t()}
  def get_coverage_report(engine) do
    case Native.native_get_coverage_report(engine) do
      {:ok, report} -> {:ok, report}
      {:error, {type, message}} -> {:error, %Error{type: type, message: message}}
    end
  end

  @doc """
  Returns the accumulated coverage report. Raises on error.
  """
  @spec get_coverage_report!(engine()) :: coverage_report()
  def get_coverage_report!(engine) do
    case get_coverage_report(engine) do
      {:ok, report} -> report
      {:error, error} -> raise error
    end
  end

  @doc """
  Clears accumulated coverage data without disabling coverage.

  Use this to reset coverage between test runs while keeping coverage enabled.

  ## Examples

      engine = Regolix.clear_coverage!(engine)
  """
  @spec clear_coverage!(engine()) :: engine()
  def clear_coverage!(engine) do
    case Native.native_clear_coverage(engine) do
      {:ok, {}} -> engine
      {:error, {type, message}} -> raise %Error{type: type, message: message}
    end
  end

  @doc """
  Executes a function with coverage tracking enabled, returning both the result and coverage.

  This is the recommended API for single-operation coverage. Coverage is automatically
  enabled before the function runs and disabled/cleared afterward.

  ## Examples

      {result, coverage} = Regolix.with_coverage(engine, fn e ->
        Regolix.eval_query!(e, "data.authz.allow")
      end)
      # result => true
      # coverage => %{"authz.rego" => %{covered: [1, 2, 5], not_covered: [9, 10]}}

  For multi-query accumulation, use the raw primitives:
  - `enable_coverage!/1`
  - `disable_coverage!/1`
  - `get_coverage_report!/1`
  - `clear_coverage!/1`
  """
  @spec with_coverage(engine(), (engine() -> result)) :: {result, coverage_report()}
        when result: var
  def with_coverage(engine, fun) when is_function(fun, 1) do
    engine = enable_coverage!(engine)
    engine = clear_coverage!(engine)

    try do
      result = fun.(engine)
      coverage = get_coverage_report!(engine)
      {result, coverage}
    after
      # Clean up: disable coverage and clear data
      disable_coverage!(engine)
      clear_coverage!(engine)
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

  @type rule_info :: %{
          name: String.t(),
          description: String.t(),
          start_line: pos_integer(),
          end_line: pos_integer()
        }

  @doc """
  Returns metadata about rules defined in loaded policies.

  Parses the policy sources to extract rule names, descriptions (from comments),
  and line ranges. Useful for mapping coverage line numbers to human-readable rule names.

  ## Examples

      rules = Regolix.get_rules(engine)
      # => %{
      #   "policy.rego" => [
      #     %{name: "allow", description: "Allow if not denied", start_line: 10, end_line: 15},
      #     %{name: "deny", description: "Deny sanctioned countries", start_line: 20, end_line: 25}
      #   ]
      # }
  """
  @spec get_rules(engine()) :: {:ok, %{String.t() => [rule_info()]}} | {:error, Error.t()}
  def get_rules(engine) do
    case Native.native_get_rules(engine) do
      {:ok, rules} -> {:ok, rules}
      {:error, {type, message}} -> {:error, %Error{type: type, message: message}}
    end
  end

  @doc """
  Returns metadata about rules defined in loaded policies. Raises on error.
  """
  @spec get_rules!(engine()) :: %{String.t() => [rule_info()]}
  def get_rules!(engine) do
    case get_rules(engine) do
      {:ok, rules} -> rules
      {:error, error} -> raise error
    end
  end

  defp encode_json(term) do
    Jason.encode(term)
  end
end
