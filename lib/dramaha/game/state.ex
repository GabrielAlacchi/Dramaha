defmodule Dramaha.Game.State do
  alias Dramaha.Game.Actions, as: Actions
  alias Dramaha.Game.Card, as: Card
  alias Dramaha.Game.Deck, as: Deck
  alias Dramaha.Game.Player, as: Player
  alias Dramaha.Game.Pot, as: Pot
  alias Dramaha.Game.Showdown, as: Showdown

  # :folded represents when everyone folded so the hand is over before showdown
  @type street() ::
          :preflop
          # A race which is preflop (all players all in no more betting)
          | :preflop_race
          | :flop
          | :draw
          # A race will never be stuck on the flop, it'll just advance straight to the draw
          # A race which is on the draw stage (all players all in no more betting)
          | :draw_race
          | :turn
          # A race which is on the turn (all players all in no more betting)
          | :turn_race
          | :river
          | :showdown
          | :folded

  @enforce_keys [:deck, :players, :pot, :player_turn, :bet_config]
  defstruct deck: Deck.full(),
            players: [],
            last_aggressor: nil,
            last_caller: nil,
            street: :preflop,
            awaiting_deal: false,
            board: [],
            bet_config: %Actions.Config{small_blind: 0, big_blind: 0},
            pot: %Pot{},
            player_turn: 0,
            showdowns: []

  @type t() :: %__MODULE__{
          deck: Deck.t(),
          players: list(Player.t()),
          last_aggressor: Player.t() | nil,
          last_caller: Player.t() | nil,
          street: street(),
          awaiting_deal: boolean(),
          board: list(Card.t()),
          bet_config: Actions.Config.t(),
          pot: Pot.t(),
          player_turn: integer(),
          showdowns: list(Showdown.t())
        }

  @spec next_street(street()) :: street()
  def next_street(:preflop), do: :flop
  def next_street(:preflop_race), do: :draw_race
  def next_street(:flop), do: :draw
  def next_street(:draw), do: :turn
  def next_street(:draw_race), do: :turn_race
  def next_street(:turn), do: :river
  def next_street(:turn_race), do: :showdown
  def next_street(:river), do: :showdown

  @spec draw_street?(t()) :: boolean()
  def draw_street?(%{street: :draw}), do: true
  def draw_street?(%{street: :draw_race}), do: true
  def draw_street?(_), do: false

  @spec current_player(t()) :: Player.t()
  def current_player(state) do
    Enum.at(state.players, state.player_turn)
  end

  @spec our_turn?(t(), integer()) :: boolean()
  def our_turn?(state, id) do
    current_player(state).player_id == id && !state.awaiting_deal
  end

  @spec racing?(t()) :: boolean()
  def racing?(%{street: :preflop_race}), do: true
  def racing?(%{street: :draw_race}), do: true
  def racing?(%{street: :turn_race}), do: true
  def racing?(_), do: false

  @spec start_new_round(t()) :: t()
  def start_new_round(state) do
    %{state | player_turn: first_player_for_round(state), last_aggressor: nil, last_caller: nil}
  end

  @spec first_player_for_round(t()) :: integer()
  def first_player_for_round(state) do
    still_in =
      Enum.with_index(state.players)
      |> Enum.filter(fn {player, _} ->
        !Player.folded?(player) && (!Player.all_in?(player) || draw_street?(state))
      end)

    case still_in do
      [{_, i} | _] ->
        i

      _ ->
        0
    end
  end

  @spec players_between(t(), Player.t(), Player.t()) :: list(Player.t())
  @doc """
  Get all the players between and including player's a and b
  """
  def players_between(state, player_a, player_b) do
    a_index = Enum.find_index(state.players, fn player -> player.seat == player_a.seat end)
    b_index = Enum.find_index(state.players, fn player -> player.seat == player_b.seat end)

    cond do
      a_index <= b_index ->
        Enum.slice(state.players, a_index..b_index)

      a_index > b_index ->
        Enum.slice(state.players, a_index..5) ++ Enum.slice(state.players, 0..b_index)
    end
  end

  @spec current_call_size(t()) :: integer()
  @doc """
  Gets the total size of calling currently
  """
  def current_call_size(%{last_aggressor: nil}), do: 0

  def current_call_size(state) do
    call_total_size =
      players_between(state, state.last_aggressor, state.last_caller)
      |> Enum.map(& &1.bet)
      |> Enum.max()

    cond do
      state.street == :preflop ->
        max(call_total_size, state.bet_config.big_blind)

      true ->
        call_total_size
    end
  end

  @spec find_next_player(t()) :: t()
  def find_next_player(%{players: players, player_turn: player_turn} = state) do
    # Look to the left of player (higher indexes in the array)
    num_players = length(players)
    players_with_idx = Enum.with_index(players)

    right_slice = Enum.slice(players_with_idx, player_turn + 1, num_players)

    # Filters out players that haven't folded and aren't already all in
    filter =
      &Enum.filter(&1, fn {player, _} ->
        # We're allowed to draw on a draw street even when all in
        !Player.folded?(player) && (draw_street?(state) || !Player.all_in?(player))
      end)

    # Find players that haven't folded on the right
    next_turn =
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

    %{state | player_turn: next_turn}
  end

  @spec big_blind_player(t()) :: integer()
  # In a heads up match the first player is the BB
  def big_blind_player(%{players: [_, _]}), do: 0
  # In a normal match the 2nd player is the BB
  def big_blind_player(_), do: 1

  @spec small_blind_player(t()) :: integer()
  # In a heads up match the first player is the SB
  def small_blind_player(%{players: [_, _]}), do: 1
  # In a normal match the 1st player is the SB
  def small_blind_player(_), do: 0

  @spec finished?(t()) :: boolean()
  def finished?(%{street: :showdown}), do: true
  def finished?(%{street: :folded}), do: true
  def finished?(_), do: false
end
