defmodule DocPrepper.Utils do
  def split_ns_path("") do
    raise "Blank name"
  end

  def split_ns_path(".") do
    []
  end

  def split_ns_path(name) when is_binary(name) do
    String.split(name, ".")
  end

  def indent_string(str, depth) when is_binary(str) do
    [String.duplicate("  ", depth), str]
  end
end
