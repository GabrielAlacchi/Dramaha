defmodule DramahaWeb.PlayLive.PlayerHandComponent do
  @moduledoc """
  Component representing a player's hand
  """
  use DramahaWeb, :live_component

  @impl true
  def update(%{play_context: play_context, cards: cards} = assigns, socket) do
    cards_selected =
      Enum.map(cards, fn {card, hidden} ->
        {{card, hidden}, Enum.member?(play_context.selected_cards, card)}
      end)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:cards_selected, cards_selected)}
  end

  @impl true
  def render(assigns) do
    ~L"""
    <div class="player--hand">
      <%= for {{card, hidden}, selected?} <- @cards_selected do %>
        <%= live_component(@socket, DramahaWeb.PlayLive.CardComponent, selectable?: @selectable?, selected?: selected?, card: card, hidden: hidden) %>
      <% end %>
    </div>
    """
  end
end
