defmodule Itertools do
  @spec combinations(integer, list(t)) :: list(list(t)) when t: var
  def combinations(0, _), do: [[]]
  def combinations(_, []), do: []

  def combinations(n, [h | t]) do
    Enum.map(combinations(n - 1, t), &[h | &1]) ++ combinations(n, t)
  end

  @spec product(list(a_type), list(b_type)) :: list({a_type, b_type})
        when a_type: var, b_type: var

  def product(a, b) do
    for x <- a, y <- b, do: {x, y}
  end
end
