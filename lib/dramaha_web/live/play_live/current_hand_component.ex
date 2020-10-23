defmodule DramahaWeb.PlayLive.CurrentHandComponent do
  @moduledoc """
  Shows the player their current hand on both the board and in hand.
  """
  alias Dramaha.Game.Poker

  use DramahaWeb, :live_component

  @impl true
  def update(%{state: state, us: us} = assigns, socket) do
    {current_board, current_in_hand} =
      case state.current_hand do
        nil ->
          {nil, nil}

        %{players: players} ->
          case Enum.find(players, fn %{player_id: id} -> id == us.player_id end) do
            nil ->
              {nil, nil}

            %{board_hand: board_hand, hand: hand} ->
              {describe_with_default(board_hand), describe_with_default(hand)}
          end
      end

    {:ok,
     assign(socket, assigns)
     |> assign(:current_board, current_board)
     |> assign(:current_in_hand, current_in_hand)}
  end

  @impl true
  def render(assigns) do
    ~L"""
    <section class="current-hand">
      <%= if @current_in_hand != nil || @current_board != nil do %>
        <h4>Your Hand</h4>
      <% end %>

      <%= if @current_in_hand != nil do %>
        <div class="current-hand--justified">
          <div>In Hand:</div>
          <div><%= @current_in_hand %></div>
        </div>
      <% end %>
      <%= if @current_board != nil do %>
      <div class="current-hand--justified">
        <div>Board Hand:</div>
        <div><%= @current_board %></div>
      </div>
      <% end %>
    </section>
    """
  end

  @spec describe_with_default(Poker.poker_hand()) :: String.t() | nil
  defp describe_with_default(poker_hand) do
    case Poker.describe(poker_hand) do
      {:ok, description} -> description
      :invalid_hand -> nil
    end
  end
end
