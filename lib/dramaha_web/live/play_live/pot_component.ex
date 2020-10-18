defmodule DramahaWeb.PlayLive.PotComponent do
  @moduledoc """
  Live Component for the Pot Size on the Table
  """
  use DramahaWeb, :live_component

  def update(%{state: state} = assigns, socket) do
    case state.current_hand do
      nil ->
        {:ok, assign(socket, assigns) |> assign(:in_hand, false)}

      %{pot: pot, showdowns: showdowns} ->
        {:ok,
         assign(socket, assigns)
         |> assign(:pot, pot)
         |> assign(:in_hand, true)
         |> assign_showdowns(state.current_hand)}
    end
  end

  def render(assigns) do
    ~L"""
      <div class="full-pot">
        <%= if @in_hand do %>
          <h2>Full Pot: <%= @pot.full_pot + @pot.committed %></h2>
        <% end %>
      </div>
      <div class="pot" id="pot">
        <%= if @in_hand do %>
          <%= for {_, pot_size} <- Enum.reverse(@pot.pots) do %>
            <div class="pot--entry">
              <div class="pot--split">
                <h2><%= pot_size %></h2>
                <div class="chip <%= chip_color_class(pot_size) %>"></div>
              </div>
            </div>
          <% end %>
          <%= for {{_, players}, idx} <- Enum.with_index(@showdowns) do %>
            <div class="pot--entry won" id="showdown-<%= idx %>">
              <%= for {seat, chips} <- players do %>
                <div class="pot--split" data-target-seat="<%= seat %>">
                  <h2><%= chips %></h2>
                  <div class="chip <%= chip_color_class(chips) %>"></div>
                </div>
              <% end %>
            </div>
          <% end %>
        <% end %>
      </div>
    """
  end

  defp assign_showdowns(socket, hand) do
    seat_shift = socket.assigns.seat_shift

    showdown_players =
      Enum.map(hand.showdowns, fn showdown ->
        Enum.zip(showdown.players, showdown.won_chips)
        |> Enum.filter(fn {_, chips} -> chips > 0 end)
        |> Enum.map(fn {player_idx, chips} ->
          player = Enum.at(hand.players, player_idx)
          shifted_seat = player.seat - seat_shift

          position =
            cond do
              shifted_seat >= 1 -> shifted_seat
              true -> shifted_seat + 6
            end

          {position, chips}
        end)
      end)

    showdown_players =
      Enum.map(showdown_players, &Enum.filter(&1, fn {_, chips} -> chips > 0 end))

    assign(socket, :showdowns, Enum.zip(hand.showdowns, showdown_players))
  end

  defp chip_color_class(pot_size) do
    cond do
      pot_size < 5 -> "chip--white"
      pot_size < 25 -> "chip--red"
      pot_size < 100 -> "chip--green"
      pot_size < 500 -> "chip--black"
      pot_size < 1000 -> "chip--purple"
      true -> "chip--yellow"
    end
  end
end
