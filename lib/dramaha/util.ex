defmodule Dramaha.Util do
  @spec capitalize(String.t()) :: String.t()
  def capitalize(str) do
    first = String.first(str) |> String.upcase()
    rest = String.slice(str, 1..String.length(str))

    first <> rest
  end

  @spec grammar_list(list(String.t())) :: String.t()
  def grammar_list([]), do: ""
  def grammar_list([word]), do: word
  def grammar_list([w_a, w_b]), do: "#{w_a} and #{w_b}"

  def grammar_list([word | rest]) do
    "#{word}, #{grammar_list(rest)}"
  end
end
