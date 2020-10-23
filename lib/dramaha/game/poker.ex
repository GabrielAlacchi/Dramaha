# Functions to evaluate hand type and strength
defmodule Dramaha.Game.Poker do
  alias Dramaha.Util
  alias Dramaha.Game.Card

  @type poker_hand_type ::
          :high_card
          | :pair
          | :two_pair
          | :three_kind
          | :straight
          | :flush
          | :full_house
          | :quad
          | :straight_flush

  # A hand is summarized by the type of hand and the kicker values
  @type poker_hand :: {poker_hand_type, integer}

  @spec evaluate(Card.holding()) :: poker_hand()
  def evaluate(holding) do
    # Assume holding is sorted descending by rank
    if flush?(holding) do
      case evaluate_straight(holding) do
        {:straight, n} ->
          {:straight_flush, n}

        :none ->
          {:flush, Tuple.to_list(holding) |> kicker_ranks |> compute_kicker_score(0)}
      end
    else
      # Find pairs, trips and above by using a mapping from count -> ranks that have that count
      card_list = Tuple.to_list(holding)

      case create_inverse_rank_map(card_list) do
        # Four of a kind
        %{4 => [quad]} ->
          {:quad, compute_kicker_score([quad | kicker_ranks(card_list, [quad])], 0)}

        # Full House, 3 and 2
        %{3 => [trip_rank], 2 => [pair_rank]} ->
          {:full_house, compute_kicker_score([trip_rank, pair_rank], 0)}

        %{3 => [trip_rank]} ->
          {:three_kind,
           compute_kicker_score([trip_rank | kicker_ranks(card_list, [trip_rank])], 0)}

        %{2 => [high_pair, low_pair]} ->
          {:two_pair,
           compute_kicker_score(
             [high_pair, low_pair | kicker_ranks(card_list, [high_pair, low_pair])],
             0
           )}

        %{2 => [pair]} ->
          {:pair, compute_kicker_score([pair | kicker_ranks(card_list, [pair])], 0)}

        _ ->
          case evaluate_straight(holding) do
            :none -> {:high_card, compute_kicker_score(kicker_ranks(card_list), 0)}
            straight -> straight
          end
      end
    end
  end

  @spec evaluate(poker_hand) :: integer
  @doc """
  Returns an integer which uniquely characterizes the strength of the hand
  """
  def hand_strength_ordinal(hand) do
    {hand_type, kicker_score} = hand

    type_ordinal =
      case hand_type do
        :high_card -> 0
        :pair -> 1
        :two_pair -> 2
        :three_kind -> 3
        :straight -> 4
        :flush -> 5
        :full_house -> 6
        :quad -> 7
        :straight_flush -> 8
      end

    # 1 billion is an overestimate of the largest possible kicker score, thus each hand type will retain
    # its strength and the kicker will settle ties.
    type_ordinal * 1_000_000_000 + kicker_score
  end

  @spec kicker_ranks(list(Card.card())) :: list(integer)
  defp kicker_ranks(cards) do
    Enum.map(cards, fn {rank, _} -> rank end)
  end

  @spec kicker_ranks(list(Card.card()), list(integer)) :: list(integer)
  defp kicker_ranks(cards, paired_ranks) do
    Enum.filter(cards, fn {rank, _} -> !Enum.member?(paired_ranks, rank) end)
    |> Enum.map(fn {rank, _} -> rank end)
  end

  @spec create_inverse_rank_map(list(Card.card())) :: map()
  defp create_inverse_rank_map(cards) do
    reducer = fn {rank, _}, counts ->
      {_, map} = Map.get_and_update(counts, rank, &{&1, (&1 || 0) + 1})

      map
    end

    rank_counts = Enum.reduce(cards, %{}, reducer)

    # Map from count to list of ranks (where the subsequent ranks are sorted descending)
    # The only case where we need to maintain sorting is 2 pair and so we don't need anything
    # too fancy here
    Enum.reduce(rank_counts, %{}, fn {rank, count}, inv_map ->
      if count == 1 do
        # Scrap anything with count 1, we'll process kickers later
        inv_map
      else
        {_, updated_map} =
          Map.get_and_update(inv_map, count, fn curr ->
            case curr do
              # Add the rank to the list that made this count
              nil -> {nil, [rank]}
              [r2] when r2 > rank -> {nil, [r2, rank]}
              [r2] when r2 < rank -> {nil, [rank, r2]}
            end
          end)

        updated_map
      end
    end)
  end

  @spec compute_kicker_score(list(integer), integer) :: integer()
  defp compute_kicker_score(kickers, acc) do
    case kickers do
      [] ->
        acc

      [rank | tl] ->
        compute_kicker_score(tl, acc * 15 + rank)
    end
  end

  @spec evaluate_straight(Card.holding()) :: {:straight, integer} | :none
  defp evaluate_straight(holding) do
    # Assume holding is sorted descending by rank and are distinct (no pairs or above)
    case holding do
      # Wheel straight, first card is an ace, second is 5 the rest must be 4, 3, 2 by default
      # given the assumed conditions
      {{14, _}, {5, _}, _, _, _} -> {:straight, 5}
      # If the top card and bottom cards are 4 apart given the initial assumed conditions it is a straight
      {{a, _}, _, _, _, {b, _}} when a - b == 4 -> {:straight, a}
      _ -> :none
    end
  end

  @spec flush?(Card.holding()) :: boolean()
  defp flush?(holding) do
    case holding do
      {{_, suit}, {_, suit}, {_, suit}, {_, suit}, {_, suit}} -> true
      _ -> false
    end
  end

  @spec describe(poker_hand()) :: {:ok, String.t()} | :invalid_hand
  def describe({hand_type, kicker_score}) do
    case describe_kickers(kicker_score) do
      {:ok, kickers} ->
        case describe_with_ranks(hand_type, kickers) do
          :invalid_hand -> :invalid_hand
          description -> {:ok, description}
        end

      {:invalid_rank, _} ->
        :invalid_hand
    end
  end

  @spec describe_with_ranks(poker_hand_type(), list(String.t())) :: String.t() | :invalid_hand
  defp describe_with_ranks(:high_card, [rank | _]), do: "#{Util.capitalize(rank)} high"
  defp describe_with_ranks(:pair, [rank | _]), do: "Pair of #{Inflex.pluralize(rank)}"

  defp describe_with_ranks(:two_pair, [top, bottom | _]),
    do: "Two pairs, #{Inflex.pluralize(top)} and #{Inflex.pluralize(bottom)}"

  defp describe_with_ranks(:three_kind, [rank | _]),
    do: "Three of a kind of #{Inflex.pluralize(rank)}"

  defp describe_with_ranks(:straight, [rank | _]), do: "#{Util.capitalize(rank)} high straight"
  defp describe_with_ranks(:flush, [rank | _]), do: "#{Util.capitalize(rank)} high flush"

  defp describe_with_ranks(:full_house, [trip, pair]),
    do: "#{Util.capitalize(Inflex.pluralize(trip))} full of #{Inflex.pluralize(pair)}"

  defp describe_with_ranks(:quad, [rank | _]), do: "Quad #{Inflex.pluralize(rank)}"
  defp describe_with_ranks(:straight_flush, ["ace" | _]), do: "Royal flush"

  defp describe_with_ranks(:straight_flush, [rank | _]),
    do: "#{Util.capitalize(rank)} high straight flush"

  defp describe_with_ranks(_, _), do: :invalid_hand

  @spec describe_kickers(integer()) :: {:ok, list(String.t())} | {:invalid_rank, integer()}
  defp describe_kickers(kicker_score) when kicker_score <= 1, do: {:invalid_rank, kicker_score}

  defp describe_kickers(kicker_score) when kicker_score < 15 do
    {:ok, description} = Card.describe_rank(kicker_score)
    {:ok, [description]}
  end

  defp describe_kickers(kicker_score) do
    floor_log = Math.log(kicker_score, 15) |> floor()

    divisor = Math.pow(15, floor_log)

    rank = Integer.floor_div(kicker_score, divisor)

    case Card.describe_rank(rank) do
      {:ok, described} ->
        case describe_kickers(Integer.mod(kicker_score, divisor)) do
          {:ok, other_kickers} ->
            {:ok, [described | other_kickers]}

          error ->
            error
        end

      {:invalid_rank, x} ->
        {:invalid_rank, x}
    end
  end
end
