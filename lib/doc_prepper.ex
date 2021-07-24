require Logger

defmodule DocPrepper do
  defmodule Types do
    defmodule Optional do
      defstruct [types: []]
    end

    defmodule Simple do
      defstruct [:name]
    end

    defmodule Array do
      defstruct [:inner]
    end
  end

  defmodule Class do
    defstruct [
      specs: %{},
    ]
  end

  defmodule Namespace do
    defstruct [
      classes: %{},
      types: %{},
      specs: %{},
    ]

    def add_class(namespace, name) do
      classes = Map.put_new(namespace.classes, name, %Class{})

      put_in(namespace.classes, classes)
    end
  end

  defmodule ExtractState do
    defstruct [
      acc: [],
      next_decorators: [],
      current_filename: nil,
      current_class: nil,
      current_namespace: ".",
      namespaces: %{
        "." => %Namespace{},
      }
    ]

    def add_to_acc(line, state) do
      %{state | acc: [line | state.acc]}
    end

    def reset_acc(state) do
      %{state | acc: []}
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

    def put_new_namespace(state, name) do
      namespaces =
        Map.put_new(state.namespaces, name, %Namespace{})

      IO.puts "PUT NAMESPACE #{name}"
      %{state | current_namespace: name, namespaces: namespaces}
    end

    def put_spec(state, name, args, return) do
      spec = {args, return}

      if state.current_class do
        IO.puts "CLASS[#{state.current_class}] SPEC #{name}"
        update_current_class(state, fn class ->
          put_in(class.specs[name], spec)
        end)
      else
        IO.puts "NAMESPACE[#{state.current_namespace}] SPEC #{name}"
        update_current_namespace(state, fn namespace ->
          put_in(namespace.specs[name], spec)
        end)
      end
    end

    def add_next_decorator(decorator, state) do
      %{state | next_decorators: [decorator, state.next_decorators]}
    end
  end

  def parse_directory(dirname) do
    lua_filenames = Path.wildcard(Path.join(dirname, "**/*.lua"))

    result =
      for filename <- lua_filenames do
        stream = File.stream!(filename)

        state = Enum.reduce(stream, new_comment_parser_state(), &extract_comment_blocks/2)
        {:none, nil, comments} = commit_comment_rows(state)

        {filename, Enum.reverse(comments)}
      end

    state = %ExtractState{}

    state =
      Enum.reduce(result, state, fn {filename, comments}, state ->
        state = %{state | current_filename: filename}
        state = ExtractState.unset_current_namespace(state)
        state = ExtractState.unset_current_class(state)
        Enum.reduce(comments, state, fn rows, state ->
          extract_metadata(IO.iodata_to_binary(rows), ExtractState.reset_acc(state))
        end)
      end)

    IO.inspect state
  end

  defp extract_comment_blocks(line, {state, comment_rows, comments}) when is_binary(line) do
    line = String.trim_leading(line)

    case line do
      <<"--", rest::binary>> ->
        comment_rows = comment_rows || []

        state = :comment

        {state, [rest | comment_rows], comments}

      _ ->
        commit_comment_rows({state, comment_rows, comments})
    end
  end

  defp new_comment_parser_state do
    # state, comment, comment blocks
    {:none, nil, []}
  end

  defp commit_comment_rows({state, comment_rows, comments}) do
    comments =
      case comment_rows do
        nil ->
          comments

        list when is_list(list) ->
          [Enum.reverse(list) | comments]
      end

    {:none, nil, comments}
  end

  defp extract_metadata("", state) do
    state
  end

  defp extract_metadata(doc, state) do
    case doc do
      <<"@", _::binary>> = line ->
        case line do
          <<"@type ", rest::binary>> ->
            {type, rest} = parse_type(rest)
            IO.inspect {:type, rest}
            extract_metadata(rest, state)

          <<"@spec ", rest::binary>> ->
            {name, args, return, rest} = parse_function_spec(String.trim_leading(rest), :start, {[], []})

            state = ExtractState.put_spec(state, name, args, return)
            extract_metadata(rest, state)

          <<"@class ", rest::binary>> ->
            {name, rest} = parse_name(trim_lspace(rest))
            state = ExtractState.put_new_class(state, name)
            extract_metadata(rest, state)

          <<"@namespace ", rest::binary>> ->
            {name, rest} = parse_name(trim_lspace(rest))
            state = ExtractState.put_new_namespace(state, name)
            extract_metadata(rest, state)

          <<"@mutative", rest::binary>> ->
            IO.inspect {{:decorator, :mutative}, rest}
            state = ExtractState.add_next_decorator(:mutative, state)
            extract_metadata(rest, state)

          <<"@example ", rest::binary>> ->
            _ = read_rest_of_line(rest)
            extract_metadata(rest, state)
        end

      doc ->
        {desc, doc} = extract_description(doc, :start, [])
        state = ExtractState.add_to_acc(desc, state)
        extract_metadata(doc, state)
    end
  end

  defp extract_description("", _, acc) do
    {Enum.reverse(acc), ""}
  end

  defp extract_description(<<"@", _::binary>> = rest, :start, acc) do
    {Enum.reverse(acc), rest}
  end

  defp extract_description(<<"\s", _::binary>> = rest, state, acc) do
    rest = String.trim_leading(rest, "\s")

    extract_description(rest, state, acc)
  end

  defp extract_description(<<"\r\n", rest::binary>>, _, acc) do
    extract_description(rest, :start, ["\r\n", acc])
  end

  defp extract_description(<<"\n", rest::binary>>, _, acc) do
    extract_description(rest, :start, ["\n", acc])
  end

  defp extract_description(<<c, rest::binary>>, _, acc) do
    extract_description(rest, :body, [<<c>> | acc])
  end

  defp parse_function_spec("", _, acc) do
    raise "incomplete function spec"
  end

  defp parse_function_spec(rest, :start, acc) do
    {name, rest} = parse_name(rest)
    {args, rest} = maybe_parse_args(rest)
    {return, rest} = case trim_lspace(rest) do
      <<":", rest::binary>> ->
        {type, rest} = parse_type(rest)
        {[type], rest}

      <<"\r\n", _::binary>> = rest ->
        {[:void], rest}

      <<"\n", _::binary>> = rest ->
        {[:void], rest}
    end

    {name, args, return, rest}
  end

  def parse_name(str) do
    do_parse_name(str, [])
  end

  defp do_parse_name("", acc) do
    {IO.iodata_to_binary(Enum.reverse(acc)), ""}
  end

  defp do_parse_name(<<c::utf8, rest::binary>>, acc) when c in ?A..?Z or
                                                          c in ?a..?z or
                                                          c == ?_ or
                                                          c == ?. or
                                                          c == ?# or
                                                          c in ?0..?9 do
    do_parse_name(rest, [<<c::utf8>> | acc])
  end

  defp do_parse_name(rest, acc) do
    {IO.iodata_to_binary(Enum.reverse(acc)), rest}
  end

  defp maybe_parse_args(rest) do
    rest = String.trim_leading(rest, "\s")

    case rest do
      <<"(", rest::binary>> ->
        {args, <<")", rest::binary>>} = parse_args(rest, [])
        {args, rest}

      rest ->
        {[], rest}
    end
  end

  defp parse_args(rest, acc) do
    rest = String.trim_leading(rest)

    {name, type, rest} = parse_arg(rest)

    acc = [{name, type} | acc]

    case rest do
      <<",", rest::binary>> ->
        parse_args(rest, acc)

      _ ->
        {Enum.reverse(acc), rest}
    end
  end

  defp parse_arg(rest) do
    rest = trim_lspace(rest)
    case parse_name(rest) do
      {name, <<":", rest::binary>>} ->
        rest = trim_lspace(rest)
        {type, rest} = parse_type(rest)
        {name, type, rest}

      {_typename, _rest} ->
        {type, rest} = parse_type(rest)
        {nil, type, rest}
    end
  end

  defp parse_type(rest) do
    {type, rest} =
      case parse_name(rest) do
        {typename, <<"<", rest::binary>>} ->
          # templated type
          {args, <<">", rest::binary>>} = parse_args(rest, [])
          template_type = {:template, typename, args}

          case rest do
            <<"[]", rest::binary>> ->
              {%Types.Array{inner: template_type}, rest}

            _ ->
              {template_type, rest}
          end

        {typename, <<"[]", rest::binary>>} ->
          element_type = %Types.Simple{name: typename}

          {%Types.Array{inner: element_type}, rest}

        {typename, rest} ->
          {%Types.Simple{name: typename}, rest}
      end

    rest = trim_lspace(rest)
    case rest do
      <<"|", rest::binary>> ->
        rest = trim_lspace(rest)
        case parse_type(rest) do
          {%Types.Optional{} = optional, rest} ->
            {%{optional | types: [type | optional.types]}, rest}

          {next_type, rest} ->
            {%Types.Optional{types: [type, next_type]}, rest}
        end

      _ ->
        {type, rest}
    end
  end

  defp trim_lspace(rest) do
    String.trim_leading(rest, "\s")
  end

  defp read_rest_of_line(rest) do
    do_read_rest_of_line(rest, [])
  end

  defp do_read_rest_of_line(<<"\r\n", rest::binary>>, acc) do
    {IO.iodata_to_binary(Enum.reverse(acc)), rest}
  end

  defp do_read_rest_of_line(<<"\n", rest::binary>>, acc) do
    {IO.iodata_to_binary(Enum.reverse(acc)), rest}
  end

  defp do_read_rest_of_line(<<c::utf8, rest::binary>>, acc) do
    do_read_rest_of_line(rest, [<<c::utf8>> | acc])
  end
end
