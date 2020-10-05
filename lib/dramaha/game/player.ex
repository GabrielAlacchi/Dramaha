defmodule Dramaha.Game.Player do
  alias Dramaha.Game.Card, as: Card

  @enforce_keys [:name, :stack]
  defstruct name: "", stack: 0, bet: 0, dealt_in: false, holding: nil

  @type t() :: %__MODULE__{
          name: String.t(),
          stack: integer(),
          bet: integer(),
          dealt_in: boolean(),
          holding: Card.holding() | nil
        }

  @spec deal_in(t(), Card.holding()) :: t()
  def deal_in(player, holding) do
    %{player | dealt_in: true, holding: holding}
  end

  @spec folded?(t()) :: boolean
  def folded?(player) do
    # We are folded if holding is nil and we've been dealt_in already
    case player do
      %{dealt_in: false} -> false
      %{holding: nil} -> true
      _ -> false
    end
  end
end
