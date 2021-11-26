defmodule DocPrepper.Document do
  alias __MODULE__, as: Document
  alias DocPrepper.ExtractState
  alias DocPrepper.FunctionSpecs
  alias DocPrepper.Namespace, as: StateNamespace
  alias DocPrepper.Class, as: StateClass

  defmodule Namespace do
    defstruct [
      aliases: %{},
      classes: %{},
      types: %{},
      consts: %{},
      specs: %FunctionSpecs{},
      members: %{},
      namespaces: %{},
    ]
  end

  def extract_state_to_document(%ExtractState{} = state) do
    add_namespaces(state.namespaces)
  end

  def add_namespaces(pairs, top \\ %Namespace{})

  def add_namespaces(namespaces, %Namespace{} = top) when is_map(namespaces) do
    add_namespaces(Map.to_list(namespaces), top)
  end

  def add_namespaces([], %Namespace{} = top) do
    top
  end

  def add_namespaces([{path, %StateNamespace{} = namespace} | rest], %Namespace{} = top) when is_binary(path) do
    add_namespaces(rest, nest_map_namespace(path, top, 0, &merge_namespaces(namespace, &1, &2)))
  end

  defp nest_map_namespace(path, %Namespace{} = top, depth, callback) when is_binary(path) do
    nest_map_namespace(split_ns_path(path), top, depth, callback)
  end

  defp nest_map_namespace([], %Namespace{} = top, depth, callback) do
    callback.(top, depth)
  end

  defp nest_map_namespace([name | rest], %Namespace{} = top, depth, callback) when is_binary(name) do
    put_in(
      top.namespaces[name],
      nest_map_namespace(rest, Map.get(top.namespaces, name, %Namespace{}), depth + 1, callback)
    )
  end

  defp nest_map_namespace_field(path, %Namespace{} = top, depth, callback) when is_binary(path) do
    nest_map_namespace_field(split_ns_path(path), top, depth, callback)
  end

  defp nest_map_namespace_field([name], %Namespace{} = top, depth, callback) when is_binary(name) do
    callback.(name, top)
  end

  defp nest_map_namespace_field([name | rest], %Namespace{} = top, depth, callback) when is_binary(name) do
    top =
      put_in(
        top.namespaces[name],
        nest_map_namespace_field(rest, Map.get(top.namespaces, name, %Namespace{}), depth + 1, callback)
      )
    top
  end

  defp merge_namespaces(%StateNamespace{} = state_ns, %Namespace{} = top, depth) do
    Enum.reduce([:aliases, :classes, :namespaces, :types, :consts, :specs, :members], top, fn
      :namespaces, top ->
        child_namespaces = state_ns.namespaces
        Enum.reduce(child_namespaces, top, fn {path, child_namespace}, top ->
          nest_map_namespace_field(path, top, depth + 1, fn name, ns when is_binary(name) ->
            merge_namespaces(child_namespace, ns, depth + 1)
          end)
        end)

      :specs, top ->
        function_specs = state_ns.specs

        Enum.reduce([:functions, :methods, :class_methods], top, fn key, top ->
          functions = Map.fetch!(function_specs, key)
          Enum.reduce(functions, top, fn {path, funcspec}, top ->
            nest_map_namespace_field(path, top, depth + 1, fn name, ns when is_binary(name) ->
              function_specs = Map.fetch!(ns, :specs)
              function_specs = FunctionSpecs.add_function(function_specs, funcspec)
              Map.put(ns, :specs, function_specs)
            end)
          end)
        end)

      property_name, top ->
        Enum.reduce(Map.fetch!(state_ns, property_name), top, fn {path, value}, top ->
          nest_map_namespace_field(path, top, depth + 1, fn name, ns when is_binary(name) ->
            map = Map.fetch!(ns, property_name)
            map = put_in(map[name], value)
            Map.put(ns, property_name, map)
          end)
        end)
    end)
  end

  defp split_ns_path("") do
    raise "Blank name"
  end

  defp split_ns_path(".") do
    []
  end

  defp split_ns_path(name) when is_binary(name) do
    String.split(name, ".")
  end

  defp indent(str, depth) do
    [String.duplicate("  ", depth), str]
  end
end
