defmodule Karakuri.Designer.Compiler do
  def compile(json) do
    Jason.decode(json)
  end
end
