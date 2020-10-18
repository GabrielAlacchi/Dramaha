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
end
