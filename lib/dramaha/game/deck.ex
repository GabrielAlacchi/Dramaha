defmodule Dramaha.Game.Deck do
  alias Dramaha.Game.Card, as: Card

  @enforce_keys [:cards]
  defstruct cards: []

  @type t() :: %__MODULE__{
          cards: list(Card.card())
        }

  @spec full() :: t()
  def full() do
    cards = cards_for_suit(:s) ++ cards_for_suit(:h) ++ cards_for_suit(:c) ++ cards_for_suit(:d)

    %Dramaha.Game.Deck{
      cards: cards
    }
  end

  @spec shuffle(t()) :: t()
  def shuffle(%Dramaha.Game.Deck{cards: cards}) do
    :random.seed(:os.timestamp())
    %Dramaha.Game.Deck{cards: Enum.shuffle(cards)}
  end

  @spec draw(t(), integer) :: {t(), list(Card.card())}
  def draw(deck, n) do
    %Dramaha.Game.Deck{cards: cards} = shuffle(deck)
    first_n = Enum.take(cards, n)
    rest_of_deck = Enum.slice(cards, n, 52)

    {%Dramaha.Game.Deck{cards: rest_of_deck}, first_n}
  end

  @spec cards_for_suit(Card.suit()) :: list(Card.card())
  defp cards_for_suit(suit) do
    for rank <- 2..14, do: {rank, suit}
  end
end
