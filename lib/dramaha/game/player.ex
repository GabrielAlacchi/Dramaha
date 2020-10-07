defmodule Dramaha.Game.Player do
  alias Dramaha.Game.Card, as: Card

  @doc """
    bet => number of chips committed during the current betting round.
    raise_by => number of chips the player raised the previous player by (used for min raise calculations)
    stack => Current player stack, always is decremented when more chips are committed.
    committed => number of chips committed so far during the full hand
                 (useful for determining which pots a player is eligible for at showdown)
    keep_decision => Does the player need to decide whether to keep or throw in a draw 1 scenario?
  """
  @enforce_keys [:name, :stack]
  defstruct name: "",
            stack: 0,
            bet: 0,
            raise_by: 0,
            committed: 0,
            dealt_in: false,
            holding: nil,
            faceup_card: nil,
            has_option: false

  @type t() :: %__MODULE__{
          name: String.t(),
          stack: integer(),
          bet: integer(),
          raise_by: integer(),
          committed: integer(),
          dealt_in: boolean(),
          holding: Card.holding() | nil,
          faceup_card: Card.t() | nil,
          has_option: boolean()
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

  @spec all_in?(t()) :: boolean()
  def all_in?(%{stack: 0}), do: true
  def all_in?(_), do: false
end
