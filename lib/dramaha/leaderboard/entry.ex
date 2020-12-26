defmodule Dramaha.Leaderboard.Entry do
  @enforce_keys [:player_name, :chips_won]
  defstruct [:player_name, :chips_won]

  @type t :: %__MODULE__{
          player_name: String.t(),
          chips_won: integer()
        }
end
