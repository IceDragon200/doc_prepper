defmodule DocPrepper.Types do
  defmodule TypedTuple do
    defstruct [
      type: nil,
      tuple: nil,
    ]
  end

  defmodule Functional do
    defstruct [
      type: nil,
      returns: nil,
    ]
  end

  defmodule Template do
    defstruct [
      :name,
      :elements,
      :arity,
    ]
  end

  defmodule Optional do
    defstruct [types: []]
  end

  defmodule Simple do
    defstruct [
      :arity, # only used for Function/*
      :name
    ]
  end

  defmodule Array do
    defstruct [:inner]
  end

  defmodule Table do
    defstruct [:fields]

    defmodule Key do
      defstruct [
        :name,
        :type,
        :is_optional,
      ]
    end

    defmodule Property do
      defstruct [
        :key,
        :value,
      ]
    end
  end

  alias DocPrepper.Arg

  def extract_name_and_template!(%Array{inner: inner}) do
    {extract_name!(inner), nil}
  end

  def extract_name_and_template!(%Simple{} = type) do
    {extract_name!(type), nil}
  end

  def extract_name_and_template!(%Template{} = type) do
    {type.name, type}
  end

  def extract_name!([type]) do
    extract_name!(type)
  end

  def extract_name!(%Arg{name: nil, type: %_{} = type}) do
    extract_name!(type)
  end

  def extract_name!(%Arg{name: name}) when is_binary(name) do
    name
  end

  def extract_name!(%Simple{name: name, arity: nil}) do
    name
  end
end
