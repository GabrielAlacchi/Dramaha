defmodule DramahaWeb.PlayLive.PotComponent do
  @moduledoc """
  Live Component for the Pot Size on the Table
  """
  use DramahaWeb, :live_component

  def update(%{state: state}, socket) do
    case state.current_hand do
      nil ->
        {:ok, assign(socket, :in_hand, false)}

      %{pot: pot} ->
        {:ok, assign(socket, :pot, pot) |> assign(:in_hand, true)}
    end
  end

  def render(assigns) do
    ~L"""
      <div class="pot" id="pot">
        <%= if @in_hand do %>
          <%= for {_, pot_size} <- Enum.reverse(@pot.pots) do %>
            <div class="pot--entry">
              <h2><%= pot_size %></h2>
              <div class="chip <%= chip_color_class(pot_size) %>"></div>
            </div>
          <% end %>
        <% end %>
      </div>
    """
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
