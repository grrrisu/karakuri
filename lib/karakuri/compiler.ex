defmodule Karakuri.Compiler do
  def compile(json) do
    Jason.decode(json)
  end
end
