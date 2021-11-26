defmodule DocPrepper.ExtractState do
  alias DocPrepper.Arg
  alias DocPrepper.FunctionSpec
  alias DocPrepper.Namespace
  #alias DocPrepper.Class

  defstruct [
    acc: [],
    next_decorators: [],
    current_filename: nil,
    current_class: nil,
    current_namespace: ".",
    namespaces: %{
      "." => %Namespace{},
    },
  ]

  @type t :: %__MODULE__{}

  def reset_state(%__MODULE__{} = state) do
    state
    |> reset_acc()
    |> reset_decorators()
    |> unset_current_class()
    |> unset_current_namespace()
  end

  def add_to_acc(line, state) do
    %{state | acc: [line | state.acc]}
  end

  def reset_acc(state) do
    %{state | acc: []}
  end

  def take_acc(state) do
    blob = String.trim(IO.iodata_to_binary(Enum.reverse(state.acc)))

    {blob, reset_acc(state)}
  end

  def take_decorators(state) do
    {state.next_decorators, reset_decorators(state)}
  end

  def reset_decorators(state) do
    %{state | next_decorators: []}
  end

  def update_current_namespace(state, mapper) do
    namespace = mapper.(state.namespaces[state.current_namespace])

    put_in(state.namespaces[state.current_namespace], namespace)
  end

  def update_current_class(state, mapper) do
    update_current_namespace(state, fn namespace ->
      class = mapper.(namespace.classes[state.current_class])
      put_in(namespace.classes[state.current_class], class)
    end)
  end

  def unset_current_class(state) do
    %{state | current_class: nil}
  end

  def put_new_class(state, name) do
    state =
      update_current_namespace(state, fn namespace ->
        Namespace.add_class(namespace, name)
      end)

    %{state | current_class: name}
  end

  def unset_current_namespace(state) do
    %{state | current_namespace: "."}
  end

  @doc """
  Maybe initialize a new namespace, if it already exists nothing happens.

  Will close the current class if it is active
  """
  @spec patch_new_namespace(t(), String.t()) :: t()
  def patch_new_namespace(%__MODULE__{} = state, name) do
    namespaces =
      Map.put_new(state.namespaces, name, %Namespace{})

    IO.puts "PUT NAMESPACE #{name}"
    %{state | current_namespace: name, namespaces: namespaces, current_class: nil}
  end

  def put_spec(state, %FunctionSpec{name: name} = funcspec) when is_binary(name) do
    if state.current_class do
      IO.puts "CLASS[#{state.current_class}] SPEC #{name}"
      update_current_class(state, fn class ->
        put_in(class.specs[name], funcspec)
      end)
    else
      IO.puts "NAMESPACE[#{state.current_namespace}] SPEC #{name}"
      update_current_namespace(state, fn namespace ->
        put_in(namespace.specs[name], funcspec)
      end)
    end
  end

  def put_alias(state, name, source) when is_binary(name) do
    if state.current_class do
      IO.puts "CLASS[#{state.current_class}] ALIAS #{name} = #{source}"
      update_current_class(state, fn class ->
        put_in(class.aliases[name], source)
      end)
    else
      IO.puts "NAMESPACE[#{state.current_namespace}] ALIAS #{name} = #{source}"
      update_current_namespace(state, fn namespace ->
        put_in(namespace.aliases[name], source)
      end)
    end
  end

  def put_type(state, %Arg{name: name} = arg) when is_binary(name) do
    if state.current_class do
      IO.puts "CLASS[#{state.current_class}] TYPE #{name} = #{inspect arg}"
      update_current_class(state, fn class ->
        put_in(class.types[name], arg)
      end)
    else
      IO.puts "NAMESPACE[#{state.current_namespace}] TYPE #{name} = #{inspect arg}"
      update_current_namespace(state, fn namespace ->
        put_in(namespace.types[name], arg)
      end)
    end
  end

  def put_const(state, %Arg{name: name} = arg) when is_binary(name) do
    if state.current_class do
      IO.puts "CLASS[#{state.current_class}] CONST #{name} = #{inspect arg}"
      update_current_class(state, fn class ->
        put_in(class.consts[name], arg)
      end)
    else
      IO.puts "NAMESPACE[#{state.current_namespace}] CONST #{name} = #{inspect arg}"
      update_current_namespace(state, fn namespace ->
        put_in(namespace.consts[name], arg)
      end)
    end
  end

  def put_member(state, %Arg{name: name} = arg) when is_binary(name) do
    if state.current_class do
      IO.puts "CLASS[#{state.current_class}] MEMBER #{name} = #{inspect arg}"
      update_current_class(state, fn class ->
        put_in(class.members[name], arg)
      end)
    else
      IO.puts "NAMESPACE[#{state.current_namespace}] MEMBER #{name} = #{inspect arg}"
      update_current_namespace(state, fn namespace ->
        put_in(namespace.members[name], arg)
      end)
    end
  end

  def add_next_decorator(decorator, state) do
    %{state | next_decorators: [decorator, state.next_decorators]}
  end
end
