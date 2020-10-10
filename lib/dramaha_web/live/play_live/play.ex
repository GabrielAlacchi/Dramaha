defmodule DramahaWeb.PlayLive.Play do
  @moduledoc """
  LiveView for creating a join form (where a user puts in their username and buy in amount)
  """
  use DramahaWeb, :live_view

  alias Dramaha.Repo
  alias Dramaha.Sessions

  @impl true
  def mount(%{"session_uuid" => uuid}, cookie_session, socket) do
    session = Sessions.get_session_by_uuid(uuid)
    socket = assign(socket, :session, session)

    case cookie_session do
      %{"player_id" => player_id} ->
        player = Repo.get(Dramaha.Sessions.Player, player_id)
        if connected?(socket), do: Sessions.subscribe(session)
        {:ok, assign(socket, :player, player) |> assign(:session, session)}

      _ ->
        {:ok, assign(socket, :player, nil)}
    end
  end

  @impl true
  def handle_params(_, _, socket) do
    case socket.assigns.player do
      nil ->
        {:noreply, push_redirect(socket, to: "/sessions/#{socket.assigns.session.uuid}/join")}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:state_update, state}, socket) do
    {:noreply, update(socket, :game_state, state)}
  end
end
