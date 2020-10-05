defmodule Dramaha.Game.ShowdownResult do
  @enforce_keys [:holding, :poker_hand, :pot_share]
  defstruct holding: {{14, :c}, {13, :c}, {12, :c}, {11, :c}, {10, :c}},
            poker_hand: {:straight_flush, 14},
            pot_share: 1

  @type t :: %__MODULE__{
          holding: Dramaha.Game.Card.holding(),
          poker_hand: Dramaha.Game.Poker.poker_hand(),
          pot_share: 0 | 1
        }
end
