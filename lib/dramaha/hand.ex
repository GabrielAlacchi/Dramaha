defmodule Dramaha.Hand do
  alias Dramaha.Game.Actions, as: Actions
  alias Dramaha.Game.Card, as: Card
  alias Dramaha.Game.Deck, as: Deck
  alias Dramaha.Game.Player, as: Player
  alias Dramaha.Game.Pot, as: Pot
  alias Dramaha.Game.Showdown, as: Showdown
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

        # This should never error out since we safely drew 5 cards. If it does we'd like to get
        # a process crashing exception to know about it.
        {:ok, holding_tuple} = Card.list_to_holding(drawn_holding)

        {
          players ++ [Player.deal_in(player, holding_tuple)],
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
          bet_config: bet_config,
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
          bet_config: bet_config,
          # Left of BB starts.
          player_turn: 2
        }

      _ ->
        :not_enough_players
    end
  end

  @spec play_action(State.t(), Actions.action()) ::
          {:ok, State.t()} | {:invalid_action, Actions.action()}
  def play_action(state, action) do
    available_actions = Actions.available_actions(state)

    if !action_allowed?(action, available_actions) do
      {:invalid_action, action}
    else
      next_state = Actions.execute_action(state, action)

      cond do
        !street_action?(action) -> {:ok, next_state}
        hand_over?(next_state) -> {:ok, close_hand(next_state)}
        action_closed?(next_state) -> {:ok, close_betting_round(next_state)}
        true -> {:ok, next_state}
      end
    end
  end

  @spec handle_next_showdown(State.t()) :: {:ok, State.t()} | :not_at_showdown | :no_more_pots
  def handle_next_showdown(%{street: :showdown} = state) do
    if Enum.empty?(state.pot.pots) do
      :no_more_pots
    else
      {pot, pot_size, eligible_idxs} = Pot.pop_showdown(state.pot, state.players)

      eligible_players = Enum.map(eligible_idxs, fn idx -> {idx, Enum.at(state.players, idx)} end)
      showdown = Showdown.evaluate_full_showdown(eligible_players, pot_size)

      # Give chips to the winners
      updated_winners =
        Enum.zip(eligible_idxs, showdown.won_chips)
        |> Enum.reduce(state.players, fn {idx, won_chips}, players_list ->
          List.update_at(players_list, idx, fn player ->
            %{player | stack: player.stack + won_chips}
          end)
        end)

      {
        :ok,
        %{state | showdowns: state.showdowns ++ [showdown], players: updated_winners, pot: pot}
      }
    end
  end

  def handle_next_showdown(_), do: :not_at_showdown

  @spec street_action?(Action.action()) :: boolean()
  defp street_action?(:deal), do: false
  defp street_action?(_), do: true

  @spec close_betting_round(State.t()) :: State.t()
  defp close_betting_round(%{players: players, pot: pot, street: street} = state) do
    {updated_pot, updated_players} = Pot.gather_bets(pot, players)

    next_state = State.start_new_round(%{state | players: updated_players, pot: updated_pot})

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
  # Non preflop there are no blinds so the logic is different
  defp action_closed?(%{players: players, player_turn: player_turn} = state) do
    # If all bets are 0 then the action is closed if and only if
    # we're back to the first player
    if Enum.all?(players, &(&1.bet == 0)) do
      player_turn == State.first_player_for_round(state)
    else
      # Check for non folded players to see if they're either all in (or matching the largest bet)
      still_in = Enum.filter(players, &(!Player.folded?(&1)))
      largest_bet = Enum.map(still_in, & &1.bet) |> Enum.max()

      all_bets_matched = Enum.all?(still_in, &(&1.stack == 0 || &1.bet == largest_bet))

      cond do
        # We have a limped pot preflop, has the big blind exercised his option?
        state.street == :preflop && largest_bet == state.bet_config.big_blind ->
          current_player = Enum.at(state.players, state.player_turn)
          all_bets_matched && !current_player.has_option

        # In a normal round (non limped pre) the round is over all players have matched the largest
        # bet or gone all in under it.
        true ->
          all_bets_matched
      end
    end
  end

  @spec action_allowed?(Actions.action(), list(Actions.action())) :: boolean()
  defp action_allowed?({:bet, size}, available_actions) do
    allowed_bets = Enum.filter(available_actions, &Actions.bet?(&1))

    case allowed_bets do
      [{:bet, min_bet}, {:bet, max_bet}] -> min_bet <= size && max_bet >= size
      [{:bet, only_bet_allowed}] -> size == only_bet_allowed
      _ -> false
    end
  end

  defp action_allowed?({:draw, discards}, available_actions) do
    cond do
      Enum.member?(available_actions, {:draw, []}) ->
        length(discards) <= 5

      true ->
        false
    end
  end

  defp action_allowed?(atom, available_actions), do: Enum.member?(available_actions, atom)

  @spec post_blinds(Player.t(), Player.t(), Actions.Config.t()) ::
          {Player.t(), Player.t(), Pot.t()}
  defp post_blinds(sb_player, bb_player, %{small_blind: sb, big_blind: bb}) do
    {sb_player, pot, _} = Actions.place_bet(sb_player, nil, nil, sb, %Pot{})
    {bb_player, pot, _} = Actions.place_bet(bb_player, nil, nil, bb, pot)

    # Give option to bb (and sb depending on the situation)
    cond do
      sb == bb ->
        # Both SB and BB have option assuming they weren't forced all in
        {give_option(sb_player), give_option(bb_player), pot}

      true ->
        {sb_player, give_option(bb_player), pot}
    end
  end

  @spec give_option(Player.t()) :: Player.t()
  # Give option to the player unless they're all in
  defp give_option(%{stack: 0} = player), do: player
  defp give_option(player), do: %{player | has_option: true}
end
