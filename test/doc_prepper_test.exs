defmodule DocPrepperTest do
  use ExUnit.Case

  describe "parse_type/1" do
    test "can parse a table declaration" do
      result =
        DocPrepper.parse_type("""
        {
          a: Integer,
          b: String,
          c: [Boolean],
          d: Node[],
        }
        """)

      IO.inspect result
    end
  end
end
