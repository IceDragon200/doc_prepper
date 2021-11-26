defmodule DocPrepper.FunctionSpec do
  defstruct [
    scope: nil,
    name: nil,
    args: [],
    return: nil,
    description: nil,
    decorators: [],
  ]
end
