defmodule Regolix.ErrorTest do
  use ExUnit.Case

  alias Regolix.Error

  test "error struct has type and message fields" do
    error = %Error{type: :parse_error, message: "bad syntax"}
    assert error.type == :parse_error
    assert error.message == "bad syntax"
  end

  test "error is an exception" do
    error = %Error{type: :eval_error, message: "undefined variable"}
    assert Exception.exception?(error)
  end

  test "error message/1 formats correctly" do
    error = %Error{type: :parse_error, message: "unexpected token"}
    assert Exception.message(error) == "parse_error: unexpected token"
  end
end
