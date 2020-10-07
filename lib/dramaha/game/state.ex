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
  def next_street(:flop), do: :draw
  def next_street(:draw), do: :turn
  def next_street(:turn), do: :river
  def next_street(:river), do: :showdown

  @spec current_player(t()) :: Player.t()
  def current_player(state) do
    Enum.at(state.players, state.player_turn)
  end

  @spec start_new_round(t()) :: t()
  def start_new_round(state) do
    %{state | player_turn: first_player_for_round(state), last_aggressor: nil, last_caller: nil}
  end

  @spec first_player_for_round(t()) :: integer()
  def first_player_for_round(%{players: players}) do
    still_in =
      Enum.with_index(players) |> Enum.filter(fn {player, _} -> !Player.folded?(player) end)

    case still_in do
      [{_, i} | _] ->
        i

      _ ->
        0
    end
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
