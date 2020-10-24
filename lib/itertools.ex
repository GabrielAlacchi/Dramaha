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

  @spec merge_by(list(t), list(t), (t -> any())) :: list(t) when t: var
  def merge_by(list_a, list_b, by_fn) do
    merge_by_tr(list_a, list_b, by_fn, [])
  end

  @spec merge_by_tr(list(t), list(t), (t -> any()), list(t)) :: list(t) when t: var
  defp merge_by_tr([], list_b, _, acc), do: acc ++ list_b
  defp merge_by_tr(list_a, [], _, acc), do: acc ++ list_a

  defp merge_by_tr([hd_a | tl_a], [hd_b | tl_b], by_fn, acc) do
    by_a = by_fn.(hd_a)
    by_b = by_fn.(hd_b)

    if by_a <= by_b do
      merge_by_tr(tl_a, [hd_b | tl_b], by_fn, acc ++ [hd_a])
    else
      merge_by_tr([hd_a | tl_a], tl_b, by_fn, acc ++ [hd_b])
    end
  end
end
