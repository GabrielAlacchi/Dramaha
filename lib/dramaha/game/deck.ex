defmodule Dramaha.Game.Deck do
  alias Dramaha.Game.Deck
  alias Dramaha.Game.Card

  @enforce_keys [:cards]
  defstruct cards: [],
            # Predraws cards is a map relating named draws to a card that has been pre-drawn
            # This is used when running out of cards in the draw phase to pin the turn and river
            predrawn_cards: %{},

            # Keep track of cards that have been folded and discarded
            folds: [],
            discards: []

  @type t() :: %__MODULE__{
          cards: list(Card.card()),
          predrawn_cards: %{atom() => Card.card()},
          folds: list(Card.card()),
          discards: list(Card.card())
        }

  @spec full() :: t()
  def full() do
    cards = cards_for_suit(:s) ++ cards_for_suit(:h) ++ cards_for_suit(:c) ++ cards_for_suit(:d)

    %Deck{
      cards: cards
    }
  end

  @spec shuffle(t()) :: t()
  def shuffle(%Deck{cards: cards} = deck) do
    :random.seed(:os.timestamp())
    %Deck{deck | cards: Enum.shuffle(cards)}
  end

  @spec draw(t(), integer, atom() | nil) :: {t(), list(Card.card())}
  def draw(deck, n, name \\ nil) do
    cond do
      is_atom(name) && Map.has_key?(deck.predrawn_cards, nil) ->
        {card, predrawn_cards} = Map.pop(deck.predrawn_cards, name)
        {%Deck{deck | predrawn_cards: predrawn_cards}, [card]}

      true ->
        %{cards: cards} = shuffle(deck)
        first_n = Enum.take(cards, n)
        rest_of_deck = Enum.slice(cards, n, 52)

        {%Deck{deck | cards: rest_of_deck}, first_n}
    end
  end

  @doc """
  This is intended to be used specifically in the draw phase
  """
  @spec replace_discards(t(), list(Card.card())) :: {t(), list(Card.card())}
  def replace_discards(deck, discards) do
    # If we draw below 2 cards, reincorporate the folds and past discards into the deck,
    # but first fix the turn and river.
    deck =
      cond do
        length(deck.cards) - length(discards) < 2 ->
          predraw_deck = predraw(deck, [:turn, :river])

          recycle_folds_and_discards(predraw_deck)

        true ->
          deck
      end

    # Draw replacements the deck
    {deck, replacements} = draw(deck, length(discards))

    cond do
      Map.has_key?(deck.predrawn_cards, :turn) ->
        # If we've already predrawn cards we'll put the discards back into the recycled deck
        # not doing so would give the player who overflowed the deck useful blocker information
        # for the next players that draw.
        {%Deck{deck | cards: deck.cards ++ discards}, replacements}

      true ->
        # Put the discards back into the discard pile
        {%Deck{deck | discards: deck.discards ++ discards}, replacements}
    end
  end

  @spec return_folded_holding(t(), Card.holding()) :: t()
  def return_folded_holding(%{folds: folds} = deck, holding) do
    %{deck | folds: folds ++ Tuple.to_list(holding)}
  end

  @spec predraw(t(), list(atom())) :: t()
  defp predraw(deck, names) do
    Enum.reduce(names, deck, fn name, acc_deck ->
      if Map.has_key?(acc_deck.predrawn_cards, name) do
        acc_deck
      else
        {acc_deck, drawn_card} = draw(acc_deck, 1)
        %{acc_deck | predrawn_cards: Map.put_new(acc_deck.predrawn_cards, name, drawn_card)}
      end
    end)
  end

  @spec recycle_folds_and_discards(t()) :: t()
  defp recycle_folds_and_discards(%{cards: cards, folds: folds, discards: discards} = deck) do
    shuffle(%{deck | cards: cards ++ folds ++ discards, folds: [], discards: []})
  end

  @spec cards_for_suit(Card.suit()) :: list(Card.card())
  defp cards_for_suit(suit) do
    for rank <- 2..14, do: {rank, suit}
  end
end
