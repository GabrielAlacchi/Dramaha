defmodule Dramaha.Game.State do
  alias Dramaha.Game.Card, as: Card
  alias Dramaha.Game.Deck, as: Deck
  alias Dramaha.Game.Player, as: Player
  alias Dramaha.Game.Pot, as: Pot

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

  @enforce_keys [:deck, :players, :pot, :player_turn, :min_bet]
  defstruct deck: Deck.full(),
            players: [],
            last_aggressor: nil,
            last_caller: nil,
            street: :preflop,
            awaiting_deal: false,
            board: [],
            min_bet: 0,
            pot: %Pot{},
            player_turn: 0

  @type t() :: %__MODULE__{
          deck: Deck.t(),
          players: list(Player.t()),
          last_aggressor: Player.t() | nil,
          last_caller: Player.t() | nil,
          min_bet: integer(),
          street: street(),
          awaiting_deal: boolean(),
          board: list(Card.t()),
          pot: Pot.t(),
          player_turn: integer()
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

  @spec finished?(t()) :: boolean()
  def finished?(%{street: :showdown}), do: true
  def finished?(%{street: :folded}), do: true
  def finished?(_), do: false
end
