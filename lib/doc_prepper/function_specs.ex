defmodule DocPrepper.FunctionSpecs do
  alias DocPrepper.FunctionSpec

  defstruct [
    functions: %{},
    methods: %{},
    class_methods: %{},
  ]

  def add_function(%__MODULE__{} = function_specs, %FunctionSpec{name: name, scope: :function} = funcspec) do
    put_in(function_specs.functions[name], funcspec)
  end

  def add_function(%__MODULE__{} = function_specs, %FunctionSpec{name: name, scope: :method} = funcspec) do
    put_in(function_specs.methods[name], funcspec)
  end

  def add_function(%__MODULE__{} = function_specs, %FunctionSpec{name: name, scope: :class_method} = funcspec) do
    put_in(function_specs.class_methods[name], funcspec)
  end
end
