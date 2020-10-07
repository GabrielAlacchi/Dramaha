defmodule Dramaha.Game.Actions do
  alias Dramaha.Game.Card, as: Card
  alias Dramaha.Game.Deck, as: Deck
  alias Dramaha.Game.Player, as: Player
  alias Dramaha.Game.Pot, as: Pot
  alias Dramaha.Game.State, as: State

  # We'll model raising as betting even though players usually distinguish these
  # it makes the code simpler
  @type action() ::
          :check
          # Used for preflop
          | :option_check
          | :fold
          | {:bet, integer()}
          | :call
          | {:draw, list(Card.t())}
          # Actions representing a draw 1 scenario where every player can see what the player drew
          # and the player has to decide to keep or throw it.
          | :keep
          | :throw
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
  def bet?(_), do: false

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

  @spec fold(Player.t()) :: Player.t()
  def fold(player) do
    %{player | holding: nil}
  end

  @spec execute_action(State.t(), action()) :: State.t()
  # FOLD Implementation
  def execute_action(%{players: players, player_turn: idx} = state, :fold) do
    updated_players = List.update_at(players, idx, &fold(&1))

    %{state | players: updated_players, player_turn: find_next_player(updated_players, idx)}
  end

  # Check Implementation
  def execute_action(%{players: players, player_turn: idx} = state, :check) do
    %{state | player_turn: find_next_player(players, idx)}
  end

  # Option Check Implementation
  def execute_action(%{players: players, player_turn: idx} = state, :option_check) do
    updated_players = List.update_at(players, idx, &%{&1 | has_option: false})
    %{state | players: updated_players, player_turn: find_next_player(players, idx)}
  end

  # Call Implementation
  def execute_action(
        %{players: players, last_caller: last_caller, player_turn: idx, pot: pot} = state,
        :call
      ) do
    player = State.current_player(state)
    %{bet: total_size} = last_caller

    # The call should be at least the size of the big blind (this handles when the big blind doesn't have enough
    # chips to post a full blind)
    call_size = max(total_size, state.bet_config.big_blind)
    {new_last_caller, pot, _} = increase_wager(player, call_size, pot)
    updated_players = List.replace_at(players, idx, new_last_caller)

    %{
      state
      | players: updated_players,
        last_caller: new_last_caller,
        player_turn: find_next_player(updated_players, idx),
        pot: pot
    }
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

    cond do
      # If the bet was aggressive update both the last aggressor and last caller
      aggressive? ->
        %{
          state
          | players: updated_players,
            last_aggressor: updated_player,
            last_caller: updated_player,
            pot: pot,
            player_turn: find_next_player(updated_players, idx)
        }

      # If the bet was not aggressive update only the last caller (treat the bet as a call)
      true ->
        %{
          state
          | players: updated_players,
            last_caller: updated_player,
            pot: pot,
            player_turn: find_next_player(updated_players, idx)
        }
    end
  end

  # Deal Implementation
  def execute_action(%{street: street, deck: deck, board: board} = state, :deal) do
    {deck, board_cards} =
      case street do
        :preflop ->
          Deck.draw(deck, 3)

        :draw ->
          Deck.draw(deck, 1)

        :turn ->
          Deck.draw(deck, 1)

        _ ->
          {deck, []}
      end

    %{
      state
      | awaiting_deal: false,
        deck: deck,
        board: board ++ board_cards,
        street: State.next_street(street)
    }
  end

  # Draw no cards is a no-op except moving to the next player
  def execute_action(%{street: :draw} = state, {:draw, []}) do
    %{state | player_turn: find_next_player(state.players, state.player_turn)}
  end

  # Draw 1 scenario (card will be faceup and player can keep or discard again)
  def execute_action(%{street: :draw, player_turn: idx} = state, {:draw, [discard]}) do
    {deck, new_players, [faceup]} = draw_cards(state.deck, state.players, idx, [discard])

    new_players = List.update_at(new_players, idx, &%{&1 | faceup_card: faceup})

    # Don't change whose turn it is
    %{state | players: new_players, deck: deck}
  end

  # Draw implementation for (discard > 1 card)
  def execute_action(%{street: :draw, deck: deck, player_turn: idx} = state, {:draw, discards}) do
    {deck, new_players, _} = draw_cards(deck, state.players, idx, discards)

    %{state | players: new_players, deck: deck, player_turn: find_next_player(new_players, idx)}
  end

  # If we keep the 1 card discard there is no change to the state other than to choose the next player
  def execute_action(%{street: :draw, players: players, player_turn: idx} = state, :keep) do
    %{state | player_turn: find_next_player(players, idx)}
  end

  # If we throw the 1 card
  def execute_action(%{street: :draw, players: players, player_turn: idx} = state, :throw) do
    %{faceup_card: faceup} = Enum.at(players, idx)
    new_players = List.replace_at(players, idx, &%{&1 | faceup_card: nil})

    {deck, new_players, _} = draw_cards(state.deck, new_players, idx, [faceup])
    %{state | deck: deck, players: new_players, player_turn: find_next_player(new_players, idx)}
  end

  @spec draw_cards(Deck.t(), list(Player.t()), integer(), list(Card.t())) ::
          {Deck.t(), list(Player.t()), list(Card.t())}
  defp draw_cards(deck, players, idx, discards) do
    {deck, replaced_cards} = Deck.draw(deck, length(discards))

    new_players =
      List.update_at(players, idx, fn %{holding: holding} = player ->
        holding_list = Tuple.to_list(holding)
        filter_discards = Enum.filter(holding_list, &(!Enum.member?(discards, &1)))
        new_holding = Card.list_to_holding(filter_discards ++ replaced_cards)

        %{player | holding: new_holding}
      end)

    {deck, new_players, replaced_cards}
  end

  @spec find_next_player(list(Player.t()), integer()) :: integer()
  defp find_next_player(players, player_turn) do
    # Look to the left of player (higher indexes in the array)
    num_players = length(players)
    players_with_idx = Enum.zip(players, 0..num_players)
    right_slice = Enum.slice(players_with_idx, player_turn + 1, num_players)

    # Filters out players that haven't folded and aren't already all in
    filter =
      &Enum.filter(&1, fn {player, _} ->
        !Player.folded?(player) && !Player.all_in?(player)
      end)

    # Find players that haven't folded on the right
    case filter.(right_slice) do
      # The first player on the right that hasn't folded is matched
      [{_, i} | _] ->
        i

      # There are no players on the right let's check the entire array
      [] ->
        case filter.(players_with_idx) do
          [{_, i} | _] -> i
          _ -> player_turn
        end
    end
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
        [:check, {:bet, stack}]

      true ->
        [:check, {:bet, min_bet}, {:bet, max_bet}]
    end
  end

  # Case 2 -- We have a last aggressor and caller. We need to determine the min raise and
  # max pot size bet and there are several other subcases to consider.
  defp available_actions(
         %{stack: stack, bet: player_bet} = player,
         %{
           last_aggressor: %{raise_by: last_raise},
           last_caller: %{bet: call_total_size},
           pot: pot
         } = state
       ) do
    # The call size must be at least a big blind preflop.
    call_total_size =
      cond do
        state.street == :preflop ->
          max(call_total_size, state.bet_config.big_blind)

        true ->
          call_total_size
      end

    # We must raise by at least a big blind. If someone goes all in for less than a big blind on a later
    # street and we want to isolate, set the minimum to at least a big blind more than the bet.
    last_raise = max(last_raise, state.bet_config.big_blind)

    # The call value is how much more we have to put in to call. If we bet and got raised we need to subtract by
    # our current bet.
    call_value = call_total_size - player_bet

    # We can bet at least last_raise more than the total amount of the call
    min_bet = call_total_size + last_raise

    pot_size_bet = pot.full_pot + pot.committed + call_value + call_total_size
    max_bet = min(pot_size_bet, stack + player_bet)

    cond do
      # It's limped to us and we have option
      player.has_option && call_value == 0 ->
        [:option_check, {:bet, min_bet}, {:bet, max_bet}]

      # We don't have enough for any raise, either fold or call all in
      stack <= call_value ->
        [:fold, :call]

      # We don't have enough to make a legal raise, we can either fold, call or commit the rest of our stack
      # If we have just enough to legally raise, it's the same.
      stack <= min_bet ->
        [:fold, :call, {:bet, stack}]

      # Otherwise we have the option of betting from a min_bet to a full pot size raise
      true ->
        # The raise will be equal to the total pot size (including committed chips by other players and ourself)
        # The amount left for us to call. Since we measure bets in the total amount, we also must add in the total
        # call size.
        [:fold, :call, {:bet, min_bet}, {:bet, max_bet}]
    end
  end

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
