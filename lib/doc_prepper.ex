require Logger

defmodule DocPrepper do
  alias DocPrepper.Document
  alias DocPrepper.ExtractState
  alias DocPrepper.Types
  alias DocPrepper.Arg
  alias DocPrepper.FunctionSpec

  @spec parse_directory(Path.t()) :: Document.t()
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
        try do
          state = %{state | current_filename: filename}
          IO.puts "FILE #{state.current_filename}"
          state =
            ExtractState.reset_state(state)

          Enum.reduce(comments, state, fn rows, state ->
            extract_metadata(IO.iodata_to_binary(rows), ExtractState.reset_acc(state))
          end)
        rescue ex ->
          reraise """
          Error occured while reading file "#{filename}"

          Caused By: #{Exception.format(:error, ex)}
          """, __STACKTRACE__
        end
      end)

    Document.extract_state_to_document(state)
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
          <<"@alias ", rest::binary>> ->
            {name, rest} = parse_name(trim_lspace(rest))
            <<"=", rest::binary>> = trim_lspace(rest)
            rest = trim_lspace(rest)
            {source, rest} = parse_name(trim_lspace(rest))
            state = ExtractState.put_alias(state, name, source)
            extract_metadata(rest, state)

          <<"@const ", rest::binary>> ->
            {arg, rest} = parse_arg(rest)
            state = ExtractState.put_const(state, arg)
            extract_metadata(rest, state)

          <<"@member ", rest::binary>> ->
            {arg, rest} = parse_arg(rest)
            state = ExtractState.put_member(state, arg)
            extract_metadata(rest, state)

          <<"@type ", rest::binary>> ->
            {arg, rest} = parse_arg(rest)
            state = ExtractState.put_type(state, arg)
            extract_metadata(rest, state)

          <<"@private.spec ", rest::binary>> ->
            {funcspec, rest} = parse_function_spec(String.trim_leading(rest), :start, {[], []})
            {description, state} = ExtractState.take_acc(state)
            {decorators, state} = ExtractState.take_decorators(state)
            _funcspec = %{funcspec | description: description, decorators: decorators}
            # TODO: maybe store private specs somewhere
            extract_metadata(rest, state)

          <<"@spec ", rest::binary>> ->
            {funcspec, rest} = parse_function_spec(String.trim_leading(rest), :start, {[], []})

            {description, state} = ExtractState.take_acc(state)
            {decorators, state} = ExtractState.take_decorators(state)
            funcspec = %{funcspec | description: description, decorators: decorators}
            state = ExtractState.put_spec(state, funcspec)
            extract_metadata(rest, state)

          <<"@class ", rest::binary>> ->
            {name, rest} = parse_name(trim_lspace(rest))
            state = ExtractState.put_new_class(state, name)
            extract_metadata(rest, state)

          <<"@namespace ", rest::binary>> ->
            {name, rest} = parse_name(trim_lspace(rest))
            state = ExtractState.patch_new_namespace(state, name)
            extract_metadata(rest, state)

          <<"@mutative", rest::binary>> ->
            IO.inspect {{:decorator, :mutative}, rest}
            state = ExtractState.add_next_decorator(:mutative, state)
            extract_metadata(rest, state)

          <<"@recursive", rest::binary>> ->
            {flag, rest} = parse_name(rest)
            IO.inspect {{:decorator, :recursive}, flag}
            state = ExtractState.add_next_decorator({:recursive, flag}, state)
            extract_metadata(rest, state)

          <<"@since ", rest::binary>> ->
            {value, rest} = parse_value(rest)
            IO.inspect {{:decorator, :since}, value}
            state = ExtractState.add_next_decorator({:since, value}, state)
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

    extract_description(rest, state, ["\s" | acc])
  end

  defp extract_description(<<"\r\n", rest::binary>>, _, acc) do
    extract_description(rest, :start, ["\r\n" | acc])
  end

  defp extract_description(<<"\n", rest::binary>>, _, acc) do
    extract_description(rest, :start, ["\n" | acc])
  end

  defp extract_description(<<c, rest::binary>>, _, acc) do
    extract_description(rest, :body, [<<c>> | acc])
  end

  defp parse_function_spec("", _, acc) do
    raise "incomplete function spec"
  end

  defp parse_function_spec(rest, :start, acc) do
    {name, rest} =
      case parse_name(rest) do
        {"", rest2} ->
          raise """
          EmptyFunctionName

          Rest:
          #{rest}
          """

        {name, rest} ->
          {name, rest}
      end

    {scope, name} =
      case name do
        <<"#", name::binary>> ->
          {"method", name}

        <<"&", name::binary>> ->
          {"class_method", name}

        <<c::utf8, _rest::binary>> = name when (c >= ?A and c <= ?Z) or (c >= ?a and c <= ?z) ->
          {"function", name}
      end

    {args, rest} = maybe_parse_args(rest)
    rest =
      case trim_lspace(rest) do
        <<":", rest::binary>> ->
          rest

        _ ->
          raise """
          Function Spec missing return type

          Name: #{name} (scope: #{scope})
          """
      end
    rest = trim_lspace(rest)
    {return, rest} = parse_arg(rest)

    {%FunctionSpec{scope: scope, name: name, args: args, return: return}, rest}
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
                                                          c == ?& or
                                                          c in ?0..?9 do
    do_parse_name(rest, [<<c::utf8>> | acc])
  end

  defp do_parse_name(rest, acc) do
    {IO.iodata_to_binary(Enum.reverse(acc)), rest}
  end

  defp maybe_parse_args(rest) do
    rest = trim_lspace(rest)

    case rest do
      <<"(", rest::binary>> ->
        case parse_args(rest, []) do
          {args, <<")", rest::binary>>} ->
            {args, rest}

          {args, rest} ->
            raise """
            ParseError, expected a closing bracket ')'

            Args (so far):
            #{inspect args}

            Rest (what's left to parse):
            #{rest}
            """
        end

      rest ->
        {nil, rest}
    end
  end

  defp parse_args(rest, acc) do
    rest = trim_lspace(rest)

    {arg, rest} = parse_arg(rest)

    acc = [arg | acc]

    case rest do
      <<",", rest::binary>> ->
        parse_args(rest, acc)

      _ ->
        {Enum.reverse(acc), rest}
    end
  end

  defp parse_arg(rest) do
    rest = trim_lspace(rest)
    {is_splat, rest} = parse_splat(rest)

    case rest do
      <<"(", _::binary>> = rest ->
        # is tuple, need to parse as args instead
        {tuple, rest} = maybe_parse_args(rest)

        {
          %Arg{
            name: nil,
            type: nil,
            tuple: tuple
          },
          rest
        }

      rest ->
        {arg, rest} = parse_arg_inner(rest)
        {%{arg | is_splat: is_splat}, rest}
    end
  end

  defp parse_arg_inner(rest) do
    {arg, rest} =
      case parse_type(rest) do
        {key_type_or_name, rest} ->
          {is_optional, rest} = parse_optional(rest)
          rest = trim_lspace(rest)

          case rest do
            <<":", rest::binary>> ->
              rest = trim_lspace(rest)
              {type, rest} = parse_type(rest)
              {is_optional2, rest} = parse_optional(rest)

              {name, template_elements} = Types.extract_name_and_template!(key_type_or_name)

              arg = %Arg{
                name: name,
                template_elements: template_elements,
                type: type,
                is_optional: is_optional || is_optional2 || false
              }
              {arg, rest}

            rest ->
              arg = %Arg{
                name: nil,
                type: key_type_or_name,
                is_optional: is_optional || false
              }
              {arg, rest}
          end
      end

    case trim_lspace(rest) do
      <<"=", rest::binary>> ->
        rest = trim_lspace(rest)
        {value, rest} = parse_value(rest)

        {%{arg | default: value}, rest}

      rest ->
        {arg, rest}
    end
  end

  defp maybe_parse_return_type(<<"=>", rest::binary>>) do
    rest = trim_lspace(rest)
    parse_type(rest)
  end

  defp maybe_parse_return_type(rest) do
    {nil, rest}
  end

  defp parse_arity(rest, state \\ :start, acc \\ [])

  defp parse_arity(<<"/", rest::binary>>, :start, acc) do
    parse_arity(rest, :start_number, acc)
  end

  defp parse_arity(rest, :start, _acc) do
    {nil, rest}
  end

  defp parse_arity(<<c::utf8, rest::binary>>, state, acc) when state in [:start_number, :number] and
                                                               c >= ?0 and c <= ?9 do
    parse_arity(rest, :number, [<<c::utf8>> | acc])
  end

  defp parse_arity(<<"+", rest::binary>>, :number, acc) do
    count = String.to_integer(IO.iodata_to_binary(Enum.reverse(acc)), 10)
    {{count, true}, rest}
  end

  defp parse_arity(<<rest::binary>>, :number, acc) do
    count = String.to_integer(IO.iodata_to_binary(Enum.reverse(acc)), 10)
    {{count, false}, rest}
  end

  defp parse_value(<<"\"", _rest::binary>> = rest) do
    parse_string(rest)
  end

  defp parse_value(<<s::utf8, "0x", _rest::binary>> = rest) when s == ?- or s == ?+ do
    parse_hex_number(rest)
  end

  defp parse_value(<<"0x", _rest::binary>> = rest) do
    parse_hex_number(rest)
  end

  defp parse_value(<<s::utf8, c::utf8, _rest::binary>> = rest)
        when (s == ?- or s == ?+) and
              c >= ?0 and c <= ?9 do
    # some kind of number
    parse_number(rest)
  end

  defp parse_value(<<c::utf8, _rest::binary>> = rest) when c >= ?0 and c <= ?9 do
    # some kind of number
    parse_number(rest)
  end

  defp parse_string(rest, state \\ :start, acc \\ [])

  defp parse_string(<<"\"", rest::binary>>, :start, acc) do
    parse_string(rest, :body, acc)
  end

  defp parse_string(<<"\"", rest::binary>>, :body, acc) do
    {{:string, IO.iodata_to_binary(Enum.reverse(acc))}, rest}
  end

  defp parse_string(<<c::utf8, rest::binary>>, :body, acc) do
    parse_string(rest, :body, [<<c::utf8>> | acc])
  end

  defp parse_hex_number(rest, state \\ :start, acc \\ [])

  defp parse_hex_number(<<s::utf8, "0x", rest::binary>>, :start, acc) when s == ?- or s == ?+ do
    parse_hex_number(rest, :body, ["0x", <<s::utf8>> | acc])
  end

  defp parse_hex_number(<<"0x", rest::binary>>, :start, acc) do
    parse_hex_number(rest, :body, ["0x" | acc])
  end

  defp parse_hex_number(<<c::utf8, rest::binary>>, :body, acc) when (c >= ?0 and c <= ?9) or
                                                                    (c >= ?a and c <= ?f) or
                                                                    (c >= ?A and c <= ?F) do
    parse_hex_number(rest, :body, [<<c::utf8>> | acc])
  end

  defp parse_hex_number(rest, :body, acc) do
    {{:hexint, IO.iodata_to_binary(Enum.reverse(acc))}, rest}
  end

  defp parse_number(rest, state \\ :integer_start, acc \\ [])

  defp parse_number(<<c::utf8, rest::binary>>, :integer_start, acc) when c == ?- or c == ?+ do
    parse_number(rest, :integer_number, [<<c::utf8>> | acc])
  end

  defp parse_number(<<c::utf8, rest::binary>>, state, acc)
        when state in [:integer_start, :integer, :integer_number] and c >= ?0 and c <= ?9 do
    parse_number(rest, :integer, [<<c::utf8>> | acc])
  end

  defp parse_number(<<c::utf8, rest::binary>>, :integer, acc) when c == ?E or c == ?e do
    parse_number(rest, :exponent_start, [<<c::utf8>> | acc])
  end

  defp parse_number(<<c::utf8, rest::binary>>, :decimal, acc) when c == ?E or c == ?e do
    parse_number(rest, :exponent_start, [<<c::utf8>> | acc])
  end

  defp parse_number(<<c::utf8, rest::binary>>, :integer, acc) when c == ?. do
    parse_number(rest, :decimal_start, [<<c::utf8>> | acc])
  end

  defp parse_number(<<c::utf8, rest::binary>>, :decimal_start, acc) when c >= ?0 and c <= ?9 do
    parse_number(rest, :decimal, [<<c::utf8>> | acc])
  end

  defp parse_number(<<c::utf8, rest::binary>>, :exponent_start, acc) when c == ?- or c == ?+ do
    parse_number(rest, :exponent_number, [<<c::utf8>> | acc])
  end

  defp parse_number(<<c::utf8, rest::binary>>, state, acc)
        when state in [:exponent_start, :exponent_number, :exponent] and c >= ?0 and c <= ?9 do
    parse_number(rest, :exponent, [<<c::utf8>> | acc])
  end

  defp parse_number(rest, state, acc) when state in [:integer, :decimal, :exponent] do
    type =
      case state do
        :integer -> :integer
        :decimal -> :decimal
        :exponent -> :decimal
      end

    {{type, IO.iodata_to_binary(Enum.reverse(acc))}, rest}
  end

  defp parse_splat(<<"...", rest::binary>>) do
    {true, rest}
  end

  defp parse_splat(rest) do
    {false, rest}
  end

  defp parse_optional(<<"?", rest::binary>>) do
    {true, rest}
  end

  defp parse_optional(rest) do
    {nil, rest}
  end

  defp parse_type(<<"{", rest::binary>>) do
    # map or table
    rest = trim_lspace(rest)
    {fields, rest} = parse_args(rest, [])
    <<"}", rest::binary>> = trim_lspace(rest)
    {%Types.Table{fields: fields}, rest}
  end

  defp parse_type(<<"[", rest::binary>>) do
    # this the alternative array syntax based on elixir's `[T]`
    rest = trim_lspace(rest)
    {inner_type, rest} = parse_args(rest, [])
    <<"]", rest::binary>> = trim_lspace(rest)
    {%Types.Array{inner: inner_type}, rest}
  end

  defp parse_type(rest) when is_binary(rest) do
    {typename, rest} = parse_name(rest)
    rest = trim_lspace(rest)

    {type, rest} =
      case rest do
        <<"<", rest::binary>> ->
          # templated type
          {args, rest} = parse_args(rest, [])
          <<">", rest::binary>> = trim_lspace(rest)

          {arity, rest} = parse_arity(rest)

          template_type = %Types.Template{
            name: typename,
            elements: args,
            arity: arity
          }

          {template_type, rest}

        rest ->
          {arity, rest} = parse_arity(rest)

          element_type = %Types.Simple{
            name: typename,
            arity: arity,
          }

          {element_type, rest}
      end

    rest = trim_lspace(rest)

    {type, rest} =
      case rest do
        <<"(", rest::binary>> ->
          {tuple, rest} = parse_args(rest, [])
          <<")", rest::binary>> = trim_lspace(rest)

          type =
            %Types.TypedTuple{
              type: type,
              tuple: tuple
            }

          {type, rest}

        rest ->
          {type, rest}
      end

    {type, rest} =
      case rest do
        <<"[]", rest::binary>> ->
          {%Types.Array{inner: type}, rest}

        rest ->
          {type, rest}
      end

    rest = trim_lspace(rest)

    {type, rest} =
      case maybe_parse_return_type(rest) do
        {nil, rest} ->
          {type, rest}

        {return_type, rest} ->
          {%Types.Functional{type: type, returns: return_type}, rest}
      end

    case trim_lspace(rest) do
      <<"|", rest::binary>> ->
        rest = trim_lspace(rest)

        case parse_type(rest) do
          {%Types.Optional{} = optional, rest} ->
            {%{optional | types: [type | optional.types]}, rest}

          {next_type, rest} ->
            {%Types.Optional{types: [type, next_type]}, rest}
        end

      rest ->
        {type, rest}
    end
  end

  defp trim_lspace(<<"\s", rest::binary>>) do
    trim_lspace(rest)
  end

  defp trim_lspace(<<"\r", rest::binary>>) do
    trim_lspace(rest)
  end

  defp trim_lspace(<<"\n", rest::binary>>) do
    trim_lspace(rest)
  end

  defp trim_lspace(rest) do
    rest
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
