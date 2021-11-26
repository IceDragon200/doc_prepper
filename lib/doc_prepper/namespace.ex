defmodule DocPrepper.Namespace do
  alias DocPrepper.FunctionSpecs

  defstruct [
    aliases: %{},
    classes: %{},
    types: %{},
    consts: %{},
    specs: %FunctionSpecs{},
    members: %{},
    namespaces: %{},
  ]

  def add_class(namespace, name) do
    put_in(namespace.classes[name], true)
  end
end

