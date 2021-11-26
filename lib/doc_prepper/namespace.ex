defmodule DocPrepper.Namespace do
  alias DocPrepper.Class

  defstruct [
    aliases: %{},
    classes: %{},
    types: %{},
    consts: %{},
    specs: %{},
    members: %{},
  ]

  def add_class(namespace, name) do
    classes = Map.put_new(namespace.classes, name, %Class{})

    put_in(namespace.classes, classes)
  end
end

