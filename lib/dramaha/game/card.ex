defmodule Dramaha.Game.Card do
  @type suit() :: :s | :h | :c | :d
  @type card() :: {integer(), suit()}

  @type holding :: {card, card, card, card, card}

  @spec parse(String.t()) :: card | {:invalid_card, String.t()}
  def parse(card_str) do
    rank_str = String.at(card_str, 0)
    suit_str = String.at(card_str, 1)

    case parse_rank(rank_str) do
      :error ->
        {:invalid_card, card_str}

      rank ->
        case parse_suit(suit_str) do
          :error -> {:invalid_card, card_str}
          suit -> {rank, suit}
        end
    end
  end

  @spec parse_holding(String.t()) :: {:ok, holding} | {:invalid_holding, String.t()}
  def parse_holding(holding_str) do
    case String.split(holding_str) do
      [c1, c2, c3, c4, c5 | _] ->
        case parse_card_list([c1, c2, c3, c4, c5], []) do
          :error ->
            {:invalid_holding, holding_str}

          card_list ->
            case sort_card_list(card_list) do
              [c1, c2, c3, c4, c5] -> {:ok, {c1, c2, c3, c4, c5}}
            end
        end

      _ ->
        {:invalid_holding, holding_str}
    end
  end

  @spec list_to_holding(list(card)) :: {:ok, holding} | :error
  def list_to_holding(cards) do
    case sort_card_list(cards) do
      [c1, c2, c3, c4, c5] -> {:ok, {c1, c2, c3, c4, c5}}
      _ -> :error
    end
  end

  @spec sort_card_list(list(card)) :: list(card)
  defp sort_card_list(cards) do
    Enum.sort_by(cards, fn {r, _} -> -r end)
  end

  @spec parse_card_list(list(String.t()), list(card)) :: list(card) | :error
  defp parse_card_list(list, acc) do
    case list do
      [] ->
        acc

      [hd | tl] ->
        case parse(hd) do
          {:invalid_card, _} -> :error
          card -> parse_card_list(tl, acc ++ [card])
        end
    end
  end

  @spec card_to_string(card()) :: String.t()
  def card_to_string({rank, suit}) do
    rank_str =
      case rank do
        14 -> "A"
        13 -> "K"
        12 -> "Q"
        11 -> "J"
        10 -> "T"
        n -> Integer.to_string(n)
      end

    "#{rank_str}#{suit}"
  end

  @spec describe_rank(integer()) :: {:ok, String.t()} | {:invalid_rank, integer()}
  def describe_rank(rank) do
    case rank do
      14 ->
        {:ok, "ace"}

      13 ->
        {:ok, "king"}

      12 ->
        {:ok, "queen"}

      11 ->
        {:ok, "jack"}

      10 ->
        {:ok, "ten"}

      9 ->
        {:ok, "nine"}

      8 ->
        {:ok, "eight"}

      7 ->
        {:ok, "seven"}

      6 ->
        {:ok, "six"}

      5 ->
        {:ok, "five"}

      4 ->
        {:ok, "four"}

      3 ->
        {:ok, "three"}

      2 ->
        {:ok, "two"}

      rank ->
        {:invalid_rank, rank}
    end
  end

  @spec parse_suit(String.t()) :: suit() | :error
  @spec parse_rank(String.t()) :: integer() | :error

  defp parse_suit("c"), do: :c
  defp parse_suit("d"), do: :d
  defp parse_suit("h"), do: :h
  defp parse_suit("s"), do: :s
  defp parse_suit(_), do: :error

  defp parse_rank("A"), do: 14
  defp parse_rank("K"), do: 13
  defp parse_rank("Q"), do: 12
  defp parse_rank("J"), do: 11
  defp parse_rank("T"), do: 10

  defp parse_rank(n) do
    case Integer.parse(n) do
      :error -> :error
      {num, _} when num < 2 -> :error
      {num, _} -> num
    end
  end
end
