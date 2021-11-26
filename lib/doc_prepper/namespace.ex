defmodule DocPrepper.Namespace do
  alias DocPrepper.FunctionSpecs
  alias __MODULE__, as: Namespace

  import DocPrepper.Utils

  defstruct [
    aliases: %{},
    classes: %{},
    types: %{},
    consts: %{},
    specs: %FunctionSpecs{},
    members: %{},
    namespaces: %{},
  ]

  def add_namespace(%Namespace{} = namespace, name) do
    tunnel_map_namespace(namespace, name, fn %Namespace{} = parent_ns, basename ->
      namespaces = Map.put_new_lazy(parent_ns.namespaces, basename, fn ->
        %Namespace{}
      end)
      put_in(parent_ns.namespaces, namespaces)
    end)
  end

  def add_class(%Namespace{} = namespace, name) do
    tunnel_map_namespace(namespace, name, fn %Namespace{} = parent_ns, basename ->
      parent_ns = put_in(parent_ns.classes[basename], true)
      namespaces = Map.put_new_lazy(parent_ns.namespaces, basename, fn ->
        %Namespace{}
      end)
      put_in(parent_ns.namespaces, namespaces)
    end)
  end

  def tunnel_map_namespace(%Namespace{} = ns, name, callback) when is_binary(name) do
    tunnel_map_namespace(ns, split_ns_path(name), callback)
  end

  def tunnel_map_namespace(%Namespace{} = ns, [name], callback) when is_binary(name) do
    callback.(ns, name)
  end

  def tunnel_map_namespace(%Namespace{} = ns, [name | rest], callback) when is_binary(name) do
    child = Map.get_lazy(ns.namespaces, name, fn ->
      %Namespace{}
    end)
    child = tunnel_map_namespace(child, rest, callback)
    put_in(ns.namespaces[name], child)
  end
end

