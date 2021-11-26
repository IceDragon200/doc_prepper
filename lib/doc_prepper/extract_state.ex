defmodule DocPrepper.ExtractState do
  alias DocPrepper.Arg
  alias DocPrepper.FunctionSpec
  alias DocPrepper.FunctionSpecs
  alias DocPrepper.Namespace

  defstruct [
    acc: [],
    next_decorators: [],
    current_filename: nil,
    current_class: nil,
    current_namespace_path: [],
    root_namespace: %Namespace{},
  ]

  alias __MODULE__, as: ExtractState

  @type t :: %__MODULE__{}

  def reset_state(%__MODULE__{} = state) do
    state
    |> reset_acc()
    |> reset_decorators()
    |> unset_current_class()
    |> unset_current_namespace()
  end

  def add_to_acc(line, %ExtractState{} = state) do
    %{state | acc: [line | state.acc]}
  end

  def reset_acc(%ExtractState{} = state) do
    %{state | acc: []}
  end

  def take_acc(%ExtractState{} = state) do
    blob = String.trim(IO.iodata_to_binary(Enum.reverse(state.acc)))

    {blob, reset_acc(state)}
  end

  def take_decorators(%ExtractState{} = state) do
    {state.next_decorators, reset_decorators(state)}
  end

  def reset_decorators(%ExtractState{} = state) do
    %{state | next_decorators: []}
  end

  def map_current_target(%ExtractState{} = state, mapper) do
    root_namespace =
      Namespace.tunnel_map_namespace(state.root_namespace, state.current_namespace_path, fn
        %Namespace{} = parent, basename ->
          namespaces = Map.put_new_lazy(parent.namespaces, basename, fn ->
            %Namespace{}
          end)
          parent = put_in(parent.namespaces, namespaces)
          namespace = Map.fetch!(parent.namespaces, basename)
          namespace =
            if state.current_class do
              Namespace.tunnel_map_namespace(namespace, state.current_class, fn %Namespace{} = parent, basename ->
                parent = put_in(parent.classes[basename], true)
                namespaces = Map.put_new_lazy(parent.namespaces, basename, fn ->
                  %Namespace{}
                end)
                parent = put_in(parent.namespaces, namespaces)
                namespace = Map.fetch!(parent.namespaces, basename)
                namespace = mapper.(namespace)
                put_in(parent.namespaces[basename], namespace)
              end)
            else
              mapper.(namespace)
            end
          put_in(parent.namespaces[basename], namespace)
      end)

    %{state | root_namespace: root_namespace}
  end

  def unset_current_class(%ExtractState{} = state) do
    %{state | current_class: nil}
  end

  def put_new_class(%ExtractState{} = state, name) when is_binary(name) do
    state =
      map_current_target(%{state | current_class: nil}, fn namespace ->
        Namespace.add_class(namespace, name)
      end)

    %{state | current_class: name}
  end

  def unset_current_namespace(%ExtractState{} = state) do
    %{state | current_namespace_path: []}
  end

  @doc """
  Maybe initialize a new namespace, if it already exists nothing happens.

  Will close the current class if it is active
  """
  @spec patch_new_namespace(t(), String.t()) :: t()
  def patch_new_namespace(%ExtractState{} = state, name) when is_binary(name) do
    root_namespace = Namespace.add_namespace(state.root_namespace, name)
    IO.puts "PUT NAMESPACE #{name}"
    %{
      state
      | current_namespace_path: name,
        root_namespace: root_namespace,
        current_class: nil
    }
  end

  def put_spec(%ExtractState{} = state, %FunctionSpec{name: name} = funcspec) when is_binary(name) do
    IO.puts "NAMESPACE[#{inspect state.current_namespace_path}] FUNC SPEC #{name}"
    map_current_target(state, fn %Namespace{} = namespace ->
      function_specs = namespace.specs
      function_specs = FunctionSpecs.add_function(function_specs, funcspec)
      put_in(namespace.specs, function_specs)
    end)
  end

  def put_alias(%ExtractState{} = state, name, source) when is_binary(name) do
    IO.puts "NAMESPACE[#{inspect state.current_namespace_path}] ALIAS #{name} = #{source}"
    map_current_target(state, fn %Namespace{} = namespace ->
      put_in(namespace.aliases[name], source)
    end)
  end

  def put_type(%ExtractState{} = state, %Arg{name: name} = arg) when is_binary(name) do
    IO.puts "NAMESPACE[#{inspect state.current_namespace_path}] TYPE #{name} = #{inspect arg}"
    map_current_target(state, fn %Namespace{} = namespace ->
      put_in(namespace.types[name], arg)
    end)
  end

  def put_const(%ExtractState{} = state, %Arg{name: name} = arg) when is_binary(name) do
    IO.puts "NAMESPACE[#{inspect state.current_namespace_path}] CONST #{name} = #{inspect arg}"
    map_current_target(state, fn %Namespace{} = namespace ->
      put_in(namespace.consts[name], arg)
    end)
  end

  def put_member(%ExtractState{} = state, %Arg{name: name} = arg) when is_binary(name) do
    IO.puts "NAMESPACE[#{inspect state.current_namespace_path}] MEMBER #{name} = #{inspect arg}"
    map_current_target(state, fn %Namespace{} = namespace ->
      put_in(namespace.members[name], arg)
    end)
  end

  def add_next_decorator(decorator, %ExtractState{} = state) do
    %{state | next_decorators: [decorator, state.next_decorators]}
  end
end
