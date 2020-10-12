# Responsible for deciding the outcomes of a given pot
defmodule Dramaha.Game.Showdown do
  alias Dramaha.Game.Card, as: Card
  alias Dramaha.Game.Poker, as: Poker
  alias Dramaha.Game.Player, as: Player

  # A pot share can be up to 2 because we are tracking both individual and
  # cumulative pot shared (in hand + board together) pot shares.
  @type pot_share() :: 0 | 1

  @spec __struct__ :: Dramaha.Game.Showdown.t()
  @enforce_keys [:pot_size, :players, :in_hand_shares, :board_shares, :total_shares, :won_chips]
  defstruct pot_size: 0,
            players: [],
            in_hand_shares: [],
            board_shares: [],
            total_shares: [],
            won_chips: []

  @type t() :: %__MODULE__{
          pot_size: integer(),
          players: list(integer()),
          in_hand_shares: list(pot_share()),
          board_shares: list(pot_share()),
          total_shares: list(integer()),
          won_chips: list(integer())
        }

  @spec evaluate_full_showdown(list({integer(), Player.t()}), integer()) :: t()
  def evaluate_full_showdown(eligible_players, pot_size) do
    board_hands = Enum.map(eligible_players, fn {_, player} -> player.board_hand end)
    in_hand_hands = Enum.map(eligible_players, fn {_, player} -> player.hand end)

    board_shares = evaluate_half_shares(board_hands)
    in_hand_shares = evaluate_half_shares(in_hand_hands)

    num_board_winners = Enum.sum(board_shares)
    num_in_hand_winners = Enum.sum(in_hand_shares)

    total_shares =
      Enum.zip(board_shares, in_hand_shares)
      |> Enum.map(fn {board_share, in_hand_share} ->
        # Numerator of a fraction addition with a different denominator
        board_share * num_in_hand_winners + in_hand_share * num_board_winners
      end)

    %Dramaha.Game.Showdown{
      pot_size: pot_size,
      players: Enum.map(eligible_players, fn {i, _} -> i end),
      board_shares: board_shares,
      in_hand_shares: in_hand_shares,
      total_shares: total_shares,
      won_chips: split_pot(pot_size, in_hand_shares, board_shares)
    }
  end

  @spec split_pot(integer(), list(pot_share()), list(pot_share())) :: list(integer())
  defp split_pot(pot_size, in_hand_shares, board_hand_shares) do
    # Split the pot in to board and in hand leaving any odd chips to the board hand
    in_hand_pot = Integer.floor_div(pot_size, 2)
    board_pot = Integer.floor_div(pot_size, 2) + Integer.mod(pot_size, 2)

    distributions =
      Enum.zip(
        split_half_pot(in_hand_pot, in_hand_shares),
        split_half_pot(board_pot, board_hand_shares)
      )

    Enum.map(distributions, fn {in_hand_winnings, board_winnings} ->
      in_hand_winnings + board_winnings
    end)
  end

  @spec split_half_pot(integer(), list(pot_share())) :: list(integer())
  defp split_half_pot(pot_size, shares) do
    denominator = Enum.sum(shares)
    size_share = Integer.floor_div(pot_size, denominator)

    # Distribute the chips
    chip_distribution = Enum.map(shares, &(&1 * size_share))

    # Handle odd chips
    total_odd_chips = Integer.mod(pot_size, denominator)

    # Give 1 odd chip to every winning player (starting closest to button)
    {chip_distribution, 0} =
      Enum.reduce(chip_distribution, {[], total_odd_chips}, fn player_share,
                                                               {distribution, odd_chips_left} ->
        case {player_share, odd_chips_left} do
          # If the player hasn't won anything then he's not entitled to odd chips
          {0, _} -> {distribution ++ [player_share], odd_chips_left}
          # If there's no odd chips left we can't give anything else
          {_, 0} -> {distribution ++ [player_share], odd_chips_left}
          # Otherwise give one of the remaining odd chips to the current player
          _ -> {distribution ++ [player_share + 1], odd_chips_left - 1}
        end
      end)

    chip_distribution
  end

  @spec evaluate_half_shares(list(Poker.poker_hand())) :: list(pot_share())
  defp evaluate_half_shares(poker_hands) do
    hand_strengths = Enum.map(poker_hands, &Poker.hand_strength_ordinal(&1))
    max_hand_strength = Enum.max(hand_strengths)

    Enum.map(hand_strengths, fn hand_strength ->
      cond do
        hand_strength == max_hand_strength -> 1
        true -> 0
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
      {:ok, current_holding} = Card.list_to_holding([h1, h2, b1, b2, b3])
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
