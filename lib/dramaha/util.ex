defmodule Dramaha.Util do
  @spec capitalize(String.t()) :: String.t()
  def capitalize(str) do
    first = String.first(str) |> String.upcase()
    rest = String.slice(str, 1..String.length(str))

    first <> rest
  end
end
