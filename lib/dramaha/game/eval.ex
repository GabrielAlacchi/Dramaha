# Responsible for deciding the outcomes of a given pot
defmodule Dramaha.Game.Eval do
  alias Dramaha.Game.Card, as: Card
  alias Dramaha.Game.Poker, as: Poker
  alias Dramaha.Game.ShowdownResult, as: ShowdownResult

  @spec evaluate_full_showdown(list(Card.holding()), list(Card.card())) :: {
          list(Dramaha.Game.ShowdownResult.t()),
          list(Dramaha.Game.ShowdownResult.t())
        }
  def evaluate_full_showdown(holdings, board) do
    {evaluate_in_hand_showdown(holdings), evaluate_board_showdown(holdings, board)}
  end

  # Determines shares of the pot which are won. Sometimes 3 way, 4 way splits are possible
  # each player gets a 1 or a 0 in the return value indicating whether they've won a share of
  # the pot.
  @spec evaluate_in_hand_showdown(list(Card.holding())) :: list(Dramaha.Game.ShowdownResult.t())
  def evaluate_in_hand_showdown(holdings) do
    poker_hands =
      Enum.map(holdings, fn holding ->
        Poker.evaluate(holding)
      end)

    hand_strengths = Enum.map(poker_hands, &Poker.hand_strength_ordinal(&1))

    max_hand_strength = Enum.max(hand_strengths)

    Enum.zip([poker_hands, holdings, hand_strengths])
    |> Enum.map(fn {hand, holding, str} ->
      case str == max_hand_strength do
        true -> %ShowdownResult{poker_hand: hand, holding: holding, pot_share: 1}
        false -> %ShowdownResult{poker_hand: hand, holding: holding, pot_share: 0}
      end
    end)
  end

  @spec evaluate_board_showdown(list(Card.holding()), list(Card.card())) ::
          list(ShowdownResult.t())
  def evaluate_board_showdown(holdings, board) do
    holdings_and_hands =
      Enum.map(holdings, fn holding ->
        best_hand_on_board(holding, board)
      end)

    hand_strengths =
      Enum.map(holdings_and_hands, fn {_, hand} -> Poker.hand_strength_ordinal(hand) end)

    max_hand_strength = Enum.max(hand_strengths)

    Enum.zip(holdings_and_hands, hand_strengths)
    |> Enum.map(fn {{hand, holding}, str} ->
      case str == max_hand_strength do
        true -> %ShowdownResult{poker_hand: hand, holding: holding, pot_share: 1}
        false -> %ShowdownResult{poker_hand: hand, holding: holding, pot_share: 0}
      end
    end)
  end

  @spec best_hand_on_board(Card.holding(), list(Card.card())) ::
          {Card.holding(), Poker.poker_hand()}
  def best_hand_on_board(holding, board) do
    # Try all groups of 2 cards from the hole and 3 from the board, there are only 100 possibilities and we're not going to need a
    # performance critical use case so this is fine.
    hole_cards = Itertools.combinations(2, Tuple.to_list(holding))
    board_cards = Itertools.combinations(3, board)

    initial_acc = {nil, {:high_card, 0}}

    Itertools.product(hole_cards, board_cards)
    |> Enum.reduce(initial_acc, fn {[h1, h2], [b1, b2, b3]},
                                   {best_holding_so_far, best_hand_so_far} ->
      current_holding = Card.list_to_holding([h1, h2, b1, b2, b3])
      current_hand = Poker.evaluate(current_holding)

      case {Poker.hand_strength_ordinal(best_hand_so_far),
            Poker.hand_strength_ordinal(current_hand)} do
        {x, y} when x > y ->
          {best_holding_so_far, best_hand_so_far}

        _ ->
          {current_holding, current_hand}
      end
    end)
  end
end
