defmodule Regolix.Error do
  @type error_type :: :parse_error | :eval_error | :json_error | :engine_error

  @type t :: %__MODULE__{
          type: error_type(),
          message: String.t()
        }

  defexception [:type, :message]

  @impl true
  def message(%__MODULE__{type: type, message: msg}) do
    "#{type}: #{msg}"
  end
end
