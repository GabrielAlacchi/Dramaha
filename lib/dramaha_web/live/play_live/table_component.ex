defmodule DramahaWeb.PlayLive.TableComponent do
  @moduledoc """
  Wraps the table portion of the UI and all the essential logic involved in rendering it.
  In particular it hands mapping from seats in the GenServer to seats in the viewport.
  All players should be in position 1 in their own screen, even if they're not in seat 1 in the actual game
  """

  use DramahaWeb, :live_component

  def update(%{state: state, player: %{id: id}} = assigns, socket) do
    us = Enum.find(state.players, &(&1.player_id == id))

    socket =
      socket
      |> assign(assigns)
      |> assign(:us, us)
      |> assign(:seat_shift, us.seat - 1)
      |> assign_seats(state)

    {:ok, assign(socket, :seat_shift, us.seat - 1)}
  end

  defp shift_seat(seat_number, seat_shift) do
    shifted = seat_number - seat_shift

    cond do
      shifted >= 1 -> shifted
      true -> shifted + 6
    end
  end

  defp assign_seats(socket, state) do
    seat_assignments =
      Enum.map(1..6, fn seat_number ->
        seated = Enum.find(state.players, fn player -> player.seat == seat_number end)

        {seat_number, seated}
      end)

    assign(socket, :seat_assignments, seat_assignments)
  end
end
