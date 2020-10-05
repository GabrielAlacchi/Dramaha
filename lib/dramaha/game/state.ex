defmodule Dramaha.Game.State do
  alias Dramaha.Game.Deck, as: Deck

  @enforce_keys [:deck, :players, :player_turn]
  defstruct deck: Deck.full(), players: [], player_turn: 0

  @type t() :: %__MODULE__{}
end
