defmodule DocPrepperTest do
  use ExUnit.Case
  doctest DocPrepper

  test "greets the world" do
    assert DocPrepper.hello() == :world
  end
end
