defmodule Dramaha.Game do
  alias Dramaha.Game.Actions, as: Actions
  alias Dramaha.Game.Deck, as: Deck
  alias Dramaha.Game.Player, as: Player
  alias Dramaha.Game.Pot, as: Pot
  alias Dramaha.Game.State, as: State

  @doc """
  Starts a new hand with the provided players, shuffles and deals and sets up the game with
  blinds posted.

  By conventions the first player in the list is the small blind (or big blind heads up)
  """
  @spec start(list(Player.t()), Actions.Config.t()) :: State.t() | :not_enough_players
  def start(players, bet_config) do
    initial_deal = {[], Deck.full()}

    {dealt_players, deck} =
      Enum.reduce(players, initial_deal, fn player, {players, current_deck} ->
        {new_deck, drawn_holding} = Deck.draw(current_deck, 5)

        {
          players ++ [Player.deal_in(player, List.to_tuple(drawn_holding))],
          new_deck
        }
      end)

    case dealt_players do
      # Heads up bb and dealer
      [bb, dealer] ->
        {sb_player, bb_player, pot} = post_blinds(dealer, bb, bet_config)

        %State{
          deck: deck,
          players: [bb_player, sb_player],
          pot: pot,
          last_aggressor: bb_player,
          last_caller: bb_player,
          min_bet: bet_config.big_blind,
          # Dealer starts
          player_turn: 1
        }

      [sb, bb | others] ->
        {sb_player, bb_player, pot} = post_blinds(sb, bb, bet_config)

        %State{
          deck: deck,
          players: [sb_player, bb_player | others],
          pot: pot,
          last_aggressor: bb_player,
          last_caller: bb_player,
          min_bet: bet_config.big_blind,
          # Left of BB starts.
          player_turn: 2
        }

      _ ->
        :not_enough_players
    end
  end

  @spec play_action(State.t(), Actions.action()) ::
          {:ok, State.t()}
          | {:game_over, State.t()}
          | {:invalid_action, Actions.action()}
  def play_action(state, action) do
    available_actions = Actions.available_actions(state)

    if action_allowed?(action, available_actions) do
      {:invalid_action, action}
    else
      next_state = Actions.execute_action(state, action)

      cond do
        hand_over?(next_state) -> {:ok, close_hand(next_state)}
        action_closed?(next_state) -> {:ok, close_betting_round(next_state)}
      end
    end
  end

  @spec close_betting_round(State.t()) :: State.t()
  defp close_betting_round(%{players: players, pot: pot, street: street} = state) do
    {updated_pot, updated_players} = Pot.gather_bets(pot, players)

    next_state = %{
      state
      | players: updated_players,
        pot: updated_pot,
        player_turn: 0,
        last_aggressor: nil,
        last_caller: nil
    }

    cond do
      street == :river -> %{next_state | awaiting_deal: false, street: :showdown}
      street == :flop -> %{next_state | awaiting_deal: false, street: :draw}
      true -> %{next_state | awaiting_deal: true}
    end
  end

  @spec close_hand(State.t()) :: State.t()
  defp close_hand(%{pot: pot, players: players, street: street} = state) do
    {updated_pot, updated_players} = Pot.gather_bets(pot, players)
    {updated_pot, updated_players} = award_sidepot_on_fold(updated_pot, updated_players)

    # The question now is do we go straight to showdown or a race?
    {next_street, awaiting_deal} =
      case {street, updated_pot.pots} do
        # If there are no further pots to contend for
        {_, []} ->
          {:folded, false}

        {:river, _} ->
          {:showdown, false}

        {:preflop, _} ->
          {:preflop_race, true}

        # If we're on the flop go straight to the draw
        {:flop, _} ->
          {:draw_race, false}

        {:turn, _} ->
          {:turn_race, true}
      end

    %{
      state
      | players: updated_players,
        pot: updated_pot,
        street: next_street,
        awaiting_deal: awaiting_deal
    }
  end

  @spec award_sidepot_on_fold(Pot.t(), list(Player.t())) :: {Pot.t(), list(Player.t())}
  defp award_sidepot_on_fold(pot, players) do
    case Pot.peek_eligible(pot, players) do
      # The winner won an additional side pot without need for a showdown (or the main pot in the case
      # everyone folded through)
      [{winner, idx}] ->
        {updated_pot, updated_player} = Pot.award_next_pot(pot, winner)
        updated_players = List.replace_at(players, idx, updated_player)

        {updated_pot, updated_players}

      _ ->
        {pot, players}
    end
  end

  @spec hand_over?(State.t()) :: boolean()
  defp hand_over?(%{players: players}) do
    can_still_bet = Enum.filter(players, &(!Player.folded?(&1) && !Player.all_in?(&1)))

    cond do
      length(can_still_bet) <= 1 -> true
      true -> false
    end
  end

  @spec action_closed?(State.t()) :: boolean()
  defp action_closed?(%{players: players, player_turn: player_turn}) do
    # If all bets are 0 then the action is closed if and only if
    # we're back to player 0.
    if Enum.all?(players, &(&1.bet == 0)) do
      player_turn == 0
    else
      # Check for non folded players to see if they're either all in (or matching the largest bet)
      still_in = Enum.filter(players, &(!Player.folded?(&1)))
      largest_bet = Enum.map(still_in, & &1.bet) |> Enum.max()

      Enum.all?(still_in, &(&1.stack == 0 || &1.bet == largest_bet))
    end
  end

  @spec action_allowed?(Actions.action(), list(Actions.action())) :: boolean()
  defp action_allowed?(:fold, available_actions), do: Enum.member?(available_actions, :fold)
  defp action_allowed?(:check, available_actions), do: Enum.member?(available_actions, :check)
  defp action_allowed?(:call, available_actions), do: Enum.member?(available_actions, :call)

  defp action_allowed?({:bet, size}, available_actions) do
    allowed_bets = Enum.filter(available_actions, &Actions.bet?(&1))

    case allowed_bets do
      [{:bet, min_bet}, {:bet, max_bet}] -> min_bet <= size && max_bet >= size
      [{:bet, only_bet_allowed}] -> size == only_bet_allowed
      _ -> false
    end
  end

  @spec post_blinds(Player.t(), Player.t(), Actions.Config.t()) ::
          {Player.t(), Player.t(), Pot.t()}
  defp post_blinds(sb_player, bb_player, %{small_blind: sb, big_blind: bb}) do
    {sb_player, pot, _} = Actions.place_bet(sb_player, nil, nil, sb, %Pot{})
    {bb_player, pot, _} = Actions.place_bet(bb_player, nil, nil, bb, pot)
    {sb_player, bb_player, pot}
  end
end