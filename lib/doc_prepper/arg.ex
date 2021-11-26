defmodule DocPrepper.Arg do
  defstruct [
    position: 0,
    name: nil,
    type: nil,
    template_elements: nil,
    is_splat: false,
    is_optional: false,
    default: nil,
    tuple: nil,
  ]
end
