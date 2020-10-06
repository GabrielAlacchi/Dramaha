defmodule Dramaha.Game.Actions do
  alias Dramaha.Game.Player, as: Player
  alias Dramaha.Game.Pot, as: Pot
  alias Dramaha.Game.State, as: State

  # We'll model raising as betting even though players usually distinguish these
  # it makes the code simpler
  @type action() :: :check | :fold | {:bet, integer()} | :call

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
    %{raise_by: raise_by} = last_aggressor || %{raise_by: 0}
    %{bet: previous_bet} = last_caller || %{bet: 0}

    increased_by = bet_size - previous_bet

    # The move is aggressive if increased_by >= raise_by, hence the 3rd member of the tuple
    {player, pot, increased_by >= raise_by}
  end

  @spec fold(Player.t()) :: Player.t()
  def fold(player) do
    %{player | holding: nil}
  end

  @spec call(Player.t(), Player.t(), Pot.t()) :: {Player.t(), Pot.t()}
  def call(player, last_caller, pot) do
    %{bet: total_size} = last_caller
    {player, pot, _} = increase_wager(player, total_size, pot)
    {player, pot}
  end

  @spec available_actions(State.t()) :: list(action())
  def available_actions(state) do
    player = Enum.at(state.players, state.player_turn)
    available_actions(player, state)
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

  # Call Implementation
  def execute_action(
        %{players: players, last_caller: last_caller, player_turn: idx, pot: pot} = state,
        :call
      ) do
    player = State.current_player(state)
    {new_last_caller, pot} = call(player, last_caller, pot)
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

  @spec find_next_player(list(Player.t()), integer()) :: integer()
  defp find_next_player(players, player_turn) do
    # Look to the left of player (higher indexes in the array)
    num_players = length(players)
    players_with_idx = Enum.zip(players, 0..num_players)
    right_slice = Enum.slice(players_with_idx, player_turn + 1, num_players)

    # Filters out players that haven't folded
    filter = &Enum.filter(&1, fn {player, _} -> !Player.folded?(player) end)

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

  @spec available_actions(Player.t(), State.t()) ::
          list(action())
  # Case 1 -- No last aggressor, we can check or bet from the BB to min(Pot, All In)
  defp available_actions(
         %{stack: stack},
         %{last_aggressor: nil, min_bet: min_bet, pot: %{full_pot: full_pot}}
       ) do
    max_bet = min(stack, full_pot)
    [:check, {:bet, min_bet}, {:bet, max_bet}]
  end

  # Case 2 -- We have a last aggressor and caller. We need to determine the min raise and
  # max pot size bet and there are several other subcases to consider.
  defp available_actions(
         %{stack: stack, bet: player_bet},
         %{
           last_aggressor: %{raise_by: last_raise},
           last_caller: %{bet: call_total_size},
           pot: pot
         }
       ) do
    # The call value is how much more we have to put in to call. If we bet and got raised we need to subtract by
    # our current bet.
    call_value = call_total_size - player_bet

    # We can bet at least last_raise more than the total amount of the call
    min_bet = call_total_size + last_raise

    cond do
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
        pot_size_bet = pot.full_pot + pot.committed + call_value + call_total_size
        max_bet = min(pot_size_bet, stack)
        [:fold, :call, {:bet, min_bet}, {:bet, max_bet}]
    end
  end

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
      %{player | stack: stack_size - increase, bet: bet + increase},
      %{pot | committed: committed + increase},
      increase
    }
  end
end
