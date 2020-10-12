defmodule DramahaWeb.PlayLive.BoardComponent do
  @moduledoc """
  Live Component for the Board, flop turn and river
  """

  use DramahaWeb, :live_component

  def update(%{state: state}, socket) do
    board_cards =
      case state.current_hand do
        nil ->
          []

        %{board: board} ->
          board
      end

    {:ok, assign(socket, :board_cards, board_cards)}
  end
end
