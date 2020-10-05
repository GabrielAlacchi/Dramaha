defmodule Dramaha.Game do
  alias Dramaha.Game.Deck, as: Deck
  alias Dramaha.Game.Player, as: Player
  alias Dramaha.Game.State, as: State

  @doc """
  Starts a new hand with the provided players, shuffles and deals and sets up the game.
  Doesn't handle blinds, that comes in a further step.
  """
  @spec start(list(Player.t())) :: State.t()
  def start(players) do
    initial_deal = {[], Deck.full()}

    {dealt_players, deck} =
      Enum.reduce(players, initial_deal, fn player, {players, current_deck} ->
        {new_deck, drawn_holding} = Deck.draw(current_deck, 5)

        {
          players ++ [Player.deal_in(player, List.to_tuple(drawn_holding))],
          new_deck
        }
      end)

    %State{
      deck: deck,
      players: dealt_players,
      player_turn: 0
    }
  end
end
