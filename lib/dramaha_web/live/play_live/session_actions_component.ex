defmodule DramahaWeb.PlayLive.SessionActionsComponent do
  @moduledoc """
  Implements Sit Out and Add On actions for the session
  """
  use DramahaWeb, :live_component

  alias Dramaha.Sessions

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_event("sit_in", _, socket) do
    Sessions.call_gameserver(
      socket.assigns.session,
      {:update_sitout, socket.assigns.us.player_id, false}
    )

    {:noreply, socket}
  end

  @impl true
  def handle_event("sit_out", _, socket) do
    Sessions.call_gameserver(
      socket.assigns.session,
      {:update_sitout, socket.assigns.us.player_id, true}
    )

    {:noreply, socket}
  end
end
