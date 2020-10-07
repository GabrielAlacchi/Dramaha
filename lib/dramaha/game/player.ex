defmodule Dramaha.Game.Player do
  alias Dramaha.Game.Card, as: Card
  alias Dramaha.Game.Showdown, as: Showdown
  alias Dramaha.Game.Poker, as: Poker

  @spec __struct__ :: Dramaha.Game.Player.t()
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
            faceup_card: nil,
            has_option: false,

            # We'll keep track of in hand and board hand as the hand progresses.
            holding: nil,
            hand: {:high_card, 0},
            board_holding: nil,
            board_hand: {:high_card, 0}

  @type t() :: %__MODULE__{
          name: String.t(),
          stack: integer(),
          bet: integer(),
          raise_by: integer(),
          committed: integer(),
          dealt_in: boolean(),
          holding: Card.holding() | nil,
          hand: Poker.poker_hand(),
          faceup_card: Card.t() | nil,
          has_option: boolean(),
          board_holding: Card.holding() | nil,
          board_hand: Poker.poker_hand()
        }

  @spec deal_in(t(), Card.holding()) :: t()
  def deal_in(player, holding) do
    %{player | dealt_in: true, holding: holding, hand: Poker.evaluate(holding)}
  end

  @spec update_board_hand(t(), list(Card.t())) :: t()
  def update_board_hand(player, board) do
    {board_holding, board_hand} = Showdown.best_hand_on_board(player.holding, board)
    %{player | board_holding: board_holding, board_hand: board_hand}
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
