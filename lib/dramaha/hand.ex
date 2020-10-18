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
      # Save that this player played this action in `last_street_action`
      current_player_idx = state.player_turn
      next_state = Actions.execute_action(state, action)

      if street_action?(action) do
        next_players =
          List.update_at(next_state.players, current_player_idx, fn player ->
            %{player | last_street_action: action}
          end)

        next_state = %{next_state | players: next_players}

        cond do
          !State.racing?(next_state) && hand_over?(next_state) -> {:ok, close_hand(next_state)}
          action_closed?(next_state) -> {:ok, close_betting_round(next_state)}
          true -> {:ok, next_state}
        end
      else
        {:ok, next_state}
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

      # For now we make the simplifying assumption that all players in a showdown will show
      # in the future we'll introduce mucking logic with the last aggressor in the pot.
      show_cards =
        Enum.reduce(eligible_idxs, state.players, fn idx, players_list ->
          List.update_at(players_list, idx, &%{&1 | show_hand: true})
        end)

      {:ok, award_showdown_chips(%{state | players: show_cards}, showdown, pot)}
    end
  end

  def handle_next_showdown(_), do: :not_at_showdown

  @spec street_action?(Action.action()) :: boolean()
  defp street_action?(:deal), do: false
  defp street_action?(_), do: true

  @spec close_betting_round(State.t()) :: State.t()
  defp close_betting_round(%{players: players, pot: pot, street: street} = state) do
    {updated_pot, updated_players} = Pot.gather_bets(pot, players)

    next_state = %{state | players: updated_players, pot: updated_pot}

    cond do
      street == :river ->
        %{next_state | awaiting_deal: false, street: :showdown}

      street == :flop ->
        State.start_new_round(%{next_state | awaiting_deal: false})

      street == :draw_race || street == :turn_race ->
        flip_cards_for_race(%{next_state | awaiting_deal: true})

      true ->
        %{next_state | awaiting_deal: true}
    end
  end

  @spec flip_cards_for_race(State.t()) :: State.t()
  defp flip_cards_for_race(state) do
    show_cards =
      Enum.map(state.players, fn player ->
        cond do
          !Player.folded?(player) -> %{player | show_hand: true}
          true -> player
        end
      end)

    %{state | players: show_cards}
  end

  @spec close_hand(State.t()) :: State.t()
  defp close_hand(%{pot: pot, players: players, street: street} = state) do
    {updated_pot, updated_players} = Pot.gather_bets(pot, players)

    updated_state = award_sidepot_on_fold(%{state | pot: updated_pot, players: updated_players})

    # The question now is do we go straight to showdown or a race?
    {next_street, awaiting_deal} =
      case {street, updated_state.pot.pots} do
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

    updated_state = %{
      updated_state
      | street: next_street,
        awaiting_deal: awaiting_deal
    }

    cond do
      next_street == :draw_race ->
        %{updated_state | player_turn: State.first_player_for_round(updated_state)}

      next_street == :turn_race ->
        flip_cards_for_race(updated_state)

      true ->
        updated_state
    end
  end

  @spec award_sidepot_on_fold(State.t()) :: State.t()
  defp award_sidepot_on_fold(state) do
    case Pot.peek_eligible(state.pot, state.players) do
      # The winner won an additional side pot without need for a showdown (or the main pot in the case
      # everyone folded through)
      [{_, idx}] ->
        {pot, pot_size, _} = Pot.pop_showdown(state.pot, state.players)

        showdown = Showdown.folded_showdown(idx, pot_size)
        award_showdown_chips(state, showdown, pot)

      _ ->
        state
    end
  end

  @spec award_showdown_chips(State.t(), Showdown.t(), Pot.t()) :: State.t()
  defp award_showdown_chips(state, showdown, pot) do
    # Give chips to the winners
    updated_winners =
      Enum.zip(showdown.players, showdown.won_chips)
      |> Enum.reduce(state.players, fn {idx, won_chips}, players_list ->
        List.update_at(players_list, idx, fn player ->
          %{player | stack: player.stack + won_chips}
        end)
      end)

    %{state | showdowns: state.showdowns ++ [showdown], players: updated_winners, pot: pot}
  end

  @spec hand_over?(State.t()) :: boolean()
  defp hand_over?(%{players: players}) do
    still_in = Enum.filter(players, &(!Player.folded?(&1)))
    largest_bet = Enum.map(still_in, & &1.bet) |> Enum.max()

    can_still_bet = Enum.filter(still_in, &(!Player.all_in?(&1)))

    # If the last remaining play with chips hasn't matched the largest stack
    case can_still_bet do
      [] ->
        true

      [only_remaining] ->
        only_remaining.bet == largest_bet

      _ ->
        false
    end
  end

  @spec action_closed?(State.t()) :: boolean()
  defp action_closed?(%{street: :draw} = state) do
    # During a draw round the action is closed if all players are either folded or done drawing
    Enum.all?(state.players, &(Player.folded?(&1) || &1.done_drawing))
  end

  defp action_closed?(%{street: :draw_race} = state), do: action_closed?(%{state | street: :draw})

  defp action_closed?(%{players: players, player_turn: player_turn} = state) do
    # If all bets are 0 then the action is closed if and only if
    # we're back to the first player
    if Enum.all?(players, &(&1.bet == 0)) do
      player_turn == State.first_player_for_round(state)
    else
      # Check for non folded players to see if they're either all in (or matching the largest bet)
      still_in = Enum.filter(players, &(!Player.folded?(&1)))
      largest_bet = Enum.map(still_in, & &1.bet) |> Enum.max()

      all_bets_matched = Enum.all?(still_in, &(Player.all_in?(&1) || &1.bet == largest_bet))

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
  defp action_allowed?({:bet, size}, available_actions),
    do: bet_or_raise_allowed?({:bet, size}, available_actions)

  defp action_allowed?({:raise, size}, available_actions),
    do: bet_or_raise_allowed?({:raise, size}, available_actions)

  defp action_allowed?({:draw, discards}, available_actions) do
    cond do
      Enum.member?(available_actions, {:draw, []}) ->
        length(discards) <= 5

      true ->
        false
    end
  end

  # All in is covered in this case because there's only one possible all in action at any given time
  defp action_allowed?(action, available_actions), do: Enum.member?(available_actions, action)

  @spec bet_or_raise_allowed?({:bet | :raise, integer()}, list(Actions.action())) :: boolean()
  # The logic is identical for whether a bet or raise is allowed
  defp bet_or_raise_allowed?({atom, size}, available_actions) do
    allowed_bets = Enum.filter(available_actions, &Actions.bet?(&1))

    # These type == atom guards ensure that we don't use {:bet, 20} instead of {:raise, 20} whenever
    # the situation requires one or the other.
    case allowed_bets do
      [{type, min_bet}, {type, max_bet}] when type == atom -> min_bet <= size && max_bet >= size
      # If the max bet is all in then the allowed action to go all in would be {:all_in, max_bet}
      # so deny any action for which max_bet >= size
      [{type, min_bet}, {:all_in, max_bet}] when type == atom -> min_bet <= size && max_bet > size
      [{type, only_bet_allowed}] when type == atom -> size == only_bet_allowed
      _ -> false
    end
  end

  @spec post_blinds(Player.t(), Player.t(), Actions.Config.t()) ::
          {Player.t(), Player.t(), Pot.t()}
  defp post_blinds(sb_player, bb_player, %{small_blind: sb, big_blind: bb}) do
    {sb_player, pot, _} = Actions.place_bet(sb_player, nil, nil, sb, %Pot{})
    {bb_player, pot, _} = Actions.place_bet(bb_player, nil, nil, bb, pot)

    sb_player = %{sb_player | last_street_action: {:small_blind, sb_player.bet}}
    bb_player = %{bb_player | last_street_action: {:big_blind, bb_player.bet}}

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
