defmodule Dramaha.Game.Actions do
  alias Dramaha.Game.Card, as: Card
  alias Dramaha.Game.Deck, as: Deck
  alias Dramaha.Game.Player, as: Player
  alias Dramaha.Game.Poker, as: Poker
  alias Dramaha.Game.Pot, as: Pot
  alias Dramaha.Game.State, as: State

  # Blind actions are not ever played by users, but are used for UI purposes
  @type action() ::
          {:small_blind, integer()}
          | {:big_blind, integer()}

          # Actual actions that can be played during a hand
          | :check
          # Used for preflop
          | :option_check
          | :fold
          | {:bet, integer()}
          # Raise and all in are equivalent to {:bet} but they will look different in the UI
          # as far as the Dramaha.Game namespace is concerned these are the exact same thing.
          | {:raise, integer()}
          | {:all_in, integer()}
          | {:call, integer()}

          # Drawing
          | {:draw, list(Card.t())}
          # Actions representing a draw 1 scenario where every player can see what the player drew
          # and the player has to decide to keep or throw it.
          | :keep
          | :throw

          # Not played by players
          | :deal

  defmodule Config do
    @enforce_keys [:small_blind, :big_blind]
    defstruct small_blind: 5, big_blind: 5

    @type t() :: %__MODULE__{
            small_blind: integer(),
            big_blind: integer()
          }
  end

  @spec bet?(action()) :: boolean()
  def bet?({:bet, _}), do: true
  def bet?({:raise, _}), do: true
  def bet?({:all_in, _}), do: true
  def bet?(_), do: false

  @doc """
  A human readable string describing an action
  """
  @spec describe(action()) :: String.t()
  def describe(action) do
    case action do
      {:small_blind, size} ->
        "Small Blind #{size}"

      {:big_blind, size} ->
        "Big Blind #{size}"

      :check ->
        "Check"

      :option_check ->
        "Check"

      {:call, size} ->
        "Call #{size}"

      :fold ->
        "Fold"

      {:bet, size} ->
        "Bet #{size}"

      {:raise, size} ->
        "Raise to #{size}"

      {:all_in, size} ->
        "All In #{size}"

      {:draw, []} ->
        "Stand Pack"

      {:draw, discards} ->
        "Draw #{length(discards)}"

      :keep ->
        "It's decent"

      :throw ->
        "Draw again"
    end
  end

  @doc """
  The atom of the action
  """
  @spec atom(action()) :: atom()
  def atom({atom, _}), do: atom
  def atom(atom), do: atom

  @doc """
  The bet size of the action
  """
  @spec size(action()) :: integer() | nil
  def size({:draw, _}), do: nil
  def size({_, s}), do: s
  def size(_), do: nil

  @doc """
  Places a bet for the player, ensuring that they're all in for less
  than the provided bet size if they don't have enough chips. This can be
  used to implement, bet, and raise actions, including blinds.

  It returns the updated player and pot structures, along with whether the player made an
  aggressive action (all ins for less than a legal raise will return false)
  """
  @spec place_bet(Player.t(), Player.t() | nil, Player.t() | nil, integer, Pot.t()) ::
          {Player.t(), Pot.t(), boolean()}
  def place_bet(player, last_aggressor, last_caller, bet_size, pot) do
    {player, pot, _} = increase_wager(player, bet_size, pot)

    # If no last aggressor raise_by is 0
    %{raise_by: last_raise} = last_aggressor || %{raise_by: 0}
    %{bet: previous_bet} = last_caller || %{bet: 0}

    increased_by = bet_size - previous_bet

    # The move is aggressive if increased_by >= raise_by, hence the 3rd member of the tuple
    cond do
      increased_by >= last_raise ->
        {
          %{player | raise_by: increased_by},
          pot,
          true
        }

      true ->
        {
          player,
          pot,
          false
        }
    end
  end

  @spec execute_action(State.t(), action()) :: State.t()
  # FOLD Implementation
  def execute_action(%{players: players, player_turn: idx} = state, :fold) do
    folding_player = Enum.at(players, idx)
    updated_players = List.update_at(players, idx, &%{&1 | holding: nil})

    State.find_next_player(%{
      state
      | players: updated_players,
        deck: Deck.return_folded_holding(state.deck, folding_player.holding)
    })
  end

  # Check Implementation
  def execute_action(state, :check) do
    State.find_next_player(state)
  end

  # Option Check Implementation
  def execute_action(%{players: players, player_turn: idx} = state, :option_check) do
    updated_players = List.update_at(players, idx, &%{&1 | has_option: false})
    State.find_next_player(%{state | players: updated_players})
  end

  # Call Implementation
  def execute_action(
        %{players: players, player_turn: idx, pot: pot} = state,
        {:call, _}
      ) do
    player = State.current_player(state)
    call_size = State.current_call_size(state)

    {new_last_caller, pot, _} = increase_wager(player, call_size, pot)
    updated_players = List.replace_at(players, idx, new_last_caller)

    State.find_next_player(%{
      state
      | players: updated_players,
        last_caller: new_last_caller,
        pot: pot
    })
  end

  # Bet Implementation
  def execute_action(
        %{
          players: players,
          last_aggressor: last_aggressor,
          last_caller: last_caller,
          player_turn: idx,
          pot: pot
        } = state,
        {:bet, bet_size}
      ) do
    player = State.current_player(state)

    {updated_player, pot, aggressive?} =
      place_bet(player, last_aggressor, last_caller, bet_size, pot)

    updated_players = List.replace_at(players, idx, updated_player)

    state =
      cond do
        # If the bet was aggressive update both the last aggressor and last caller
        aggressive? ->
          %{
            state
            | players: updated_players,
              last_aggressor: updated_player,
              last_caller: updated_player,
              pot: pot
          }

        # If the bet was not aggressive update only the last caller (treat the bet as a call)
        true ->
          %{
            state
            | players: updated_players,
              last_caller: updated_player,
              pot: pot
          }
      end

    State.find_next_player(state)
  end

  # Raise / All In are equivalent to betting, they're simply named as such for display
  # purposes
  def execute_action(state, {:raise, size}), do: execute_action(state, {:bet, size})
  def execute_action(state, {:all_in, size}), do: execute_action(state, {:bet, size})

  # Deal Implementation
  def execute_action(%{street: street, deck: deck, board: board} = state, :deal) do
    {deck, board_cards} =
      case street do
        :preflop ->
          Deck.draw(deck, 3)

        :preflop_race ->
          Deck.draw(deck, 3)

        :draw ->
          Deck.draw(deck, 1, :turn)

        :draw_race ->
          Deck.draw(deck, 1, :turn)

        :turn ->
          Deck.draw(deck, 1, :river)

        :turn_race ->
          Deck.draw(deck, 1, :river)

        _ ->
          {deck, []}
      end

    updated_board = board ++ board_cards

    # Update board hand evaluation for every player that is still in the hold
    updated_players =
      Enum.map(state.players, fn player ->
        Player.update_board_hand(player, updated_board)
      end)

    updated_state = %{
      state
      | awaiting_deal: false,
        players: updated_players,
        deck: deck,
        board: updated_board
    }

    State.start_new_round(updated_state)
  end

  # Draw no cards is a no-op except moving to the next player
  def execute_action(state, {:draw, []}) do
    players =
      List.update_at(state.players, state.player_turn, fn player ->
        %{player | done_drawing: true}
      end)

    State.find_next_player(%{state | players: players})
  end

  # Draw 1 scenario (card will be faceup and player can keep or discard again)
  def execute_action(%{player_turn: idx} = state, {:draw, [discard]}) do
    {state, [faceup]} = draw_cards(state, [discard])

    new_players =
      List.update_at(state.players, idx, &%{&1 | faceup_card: faceup, done_drawing: false})

    # Don't change whose turn it is
    %{state | players: new_players}
  end

  # Draw implementation for (discard > 1 card)
  def execute_action(state, {:draw, discards}) do
    {state, _} = draw_cards(state, discards)

    State.find_next_player(state)
  end

  # If we keep the 1 card discard it's equivalent to standing pat.
  def execute_action(state, :keep), do: execute_action(state, {:draw, []})

  # If we throw the 1 card
  def execute_action(state, :throw) do
    %{faceup_card: faceup} = State.current_player(state)

    new_players =
      List.update_at(
        state.players,
        state.player_turn,
        &%{&1 | faceup_card: nil, done_drawing: true}
      )

    {state, _} = draw_cards(%{state | players: new_players}, [faceup])
    State.find_next_player(state)
  end

  @spec draw_cards(State.t(), list(Card.t())) :: {State.t(), list(Card.t())}
  defp draw_cards(state, discards) do
    {deck, replaced_cards} = Deck.replace_discards(state.deck, discards)

    new_players =
      List.update_at(state.players, state.player_turn, fn player ->
        {new_dealt_cards, _} =
          Enum.reduce(player.dealt_cards, {[], replaced_cards}, fn holding_card,
                                                                   {dealt_cards, new_cards} ->
            if Enum.member?(discards, holding_card) do
              [next_new_card | rest] = new_cards
              {dealt_cards ++ [next_new_card], rest}
            else
              {dealt_cards ++ [holding_card], new_cards}
            end
          end)

        IO.puts("[Debug Dump]")
        IO.inspect(discards)
        IO.inspect(replaced_cards)
        IO.inspect(new_dealt_cards)

        {:ok, new_holding} = Card.list_to_holding(new_dealt_cards)

        player_updated_in_hand = %{
          player
          | holding: new_holding,
            hand: Poker.evaluate(new_holding),
            dealt_cards: new_dealt_cards,
            done_drawing: true
        }

        Player.update_board_hand(player_updated_in_hand, state.board)
      end)

    {
      %{state | deck: deck, players: new_players},
      replaced_cards
    }
  end

  @spec available_actions(State.t()) :: list(action())
  def available_actions(state) do
    cond do
      State.finished?(state) ->
        []

      true ->
        case state do
          %{awaiting_deal: true} ->
            [:deal]

          %{street: draw} when draw == :draw or draw == :draw_race ->
            player = Enum.at(state.players, state.player_turn)
            available_draw_actions(player)

          _ ->
            player = Enum.at(state.players, state.player_turn)
            available_actions(player, state)
        end
    end
  end

  @spec available_actions(Player.t(), State.t()) ::
          list(action())
  # Case 1 -- No last aggressor, we can check or bet from the BB to min(Pot, All In)
  defp available_actions(
         %{stack: stack},
         %{last_aggressor: nil, bet_config: %{big_blind: min_bet}, pot: %{full_pot: full_pot}}
       ) do
    max_bet = min(stack, full_pot)

    cond do
      stack <= min_bet ->
        [:check, {:all_in, stack}]

      true ->
        [:check, {:bet, min_bet}, max_bet_action(max_bet, stack, :bet, 0)]
    end
  end

  # Case 2 -- We have a last aggressor and caller. We need to determine the min raise and
  # max pot size bet and there are several other subcases to consider.
  defp available_actions(
         %{stack: stack, bet: player_bet} = player,
         %{
           last_aggressor: last_aggressor,
           pot: pot
         } = state
       ) do
    # The call size must be at least a big blind preflop.
    call_total_size = State.current_call_size(state)

    # We must raise by at least a big blind. If someone goes all in for less than a big blind on a later
    # street and we want to isolate, set the minimum to at least a big blind more than the bet.
    last_raise = max(last_aggressor.raise_by, state.bet_config.big_blind)

    # The call value is how much more we have to put in to call. If we bet and got raised we need to subtract by
    # our current bet.
    call_value = call_total_size - player_bet

    # We can bet at least last_raise more than the total amount of the call
    min_bet = call_total_size + last_raise

    pot_size_bet = pot.full_pot + pot.committed + call_value + call_total_size
    max_bet = min(pot_size_bet, stack + player_bet)

    # If all other players are either all in or folded we can't raise, we can only call
    # Alternatively if our bet matches the last aggressor's bet we can only fold or call.
    # The latter case happens if players went all in for under a legal raise.
    cant_raise? =
      Enum.all?(
        state.players,
        &(&1.player_id == player.player_id || Player.all_in?(&1) || Player.folded?(&1))
      ) || last_aggressor.bet == player_bet

    cond do
      # It's limped to us and we have option
      player.has_option && call_value == 0 ->
        [:option_check, {:raise, min_bet}, max_bet_action(max_bet, stack, :raise, player_bet)]

      # We don't have enough for any raise, either fold or call all in
      stack <= call_value || cant_raise? ->
        [:fold, {:call, min(stack, call_value)}]

      # We don't have enough to make a legal raise, we can either fold, call or commit the rest of our stack
      # If we have just enough to legally raise, it's the same.
      stack + player_bet <= min_bet ->
        [:fold, {:call, call_value}, {:all_in, stack + player_bet}]

      # Otherwise we have the option of betting from a min_bet to a full pot size raise
      true ->
        # The raise will be equal to the total pot size (including committed chips by other players and ourself)
        # The amount left for us to call. Since we measure bets in the total amount, we also must add in the total
        # call size.
        [
          :fold,
          {:call, call_value},
          {:raise, min_bet},
          max_bet_action(max_bet, stack, :raise, player_bet)
        ]
    end
  end

  @spec default_action(State.t()) :: action()
  def default_action(state) do
    case available_actions(state) do
      [:fold | _] -> :fold
      [:check | _] -> :check
      [:option_check | _] -> :option_check
      # Draw Situations
      [{:draw, []}] -> {:draw, []}
      [:keep, :throw] -> :keep
    end
  end

  @spec max_bet_action(integer(), integer(), :raise | :bet, integer()) :: action()
  defp max_bet_action(max_bet, stack, _, player_bet) when max_bet >= stack + player_bet,
    do: {:all_in, stack + player_bet}

  defp max_bet_action(max_bet, _, action_type, _), do: {action_type, max_bet}

  @spec available_draw_actions(Player.t()) :: list(action())
  defp available_draw_actions(%{faceup_card: nil}), do: [{:draw, []}]
  defp available_draw_actions(%{faceup_card: _}), do: [:keep, :throw]

  # Sets the total amount of money layed by a player in the current round to total_size,
  # ensuring that they're all in for less than the provided bet size if they don't have enough chips.
  # This can be used to implement, call, bet, and raise actions, including blinds.

  # It returns the updated player, pot and how much the wager was increased by
  @spec increase_wager(Player.t(), integer(), Pot.t()) :: {Player.t(), Pot.t(), integer}
  defp increase_wager(player, total_size, pot) do
    # Bet represents amount bet in the current round
    %{stack: stack_size, bet: bet} = player
    %{committed: committed} = pot

    # Since stack will be decremented everytime we bet, the max we can bet at any time
    # is the stack_size.
    increase = min(total_size - bet, stack_size)

    {
      %{
        player
        | stack: stack_size - increase,
          bet: bet + increase,
          committed: player.committed + increase
      },
      %{pot | committed: committed + increase},
      increase
    }
  end
end
