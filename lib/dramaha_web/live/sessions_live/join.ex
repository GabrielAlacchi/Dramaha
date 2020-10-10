defmodule DramahaWeb.SessionsLive.Join do
  @moduledoc """
  LiveView for creating a join form (where a user puts in their username and buy in amount)
  """
  use DramahaWeb, :live_view

  alias Dramaha.Sessions

  @impl true
  def mount(%{"session_uuid" => uuid} = _params, live_session, socket) do
    {uuid, socket} =
      case live_session do
        # This will lead to a redirect in handle_params
        %{"session_uuid" => session_uuid, "player_id" => player_id} ->
          {session_uuid, socket |> assign(:player_id, player_id)}

        _ ->
          {uuid, socket}
      end

    session = Sessions.get_session_by_uuid(uuid)

    {:ok, socket |> assign(:session, session)}
  end

  @impl true
  def handle_params(_params, _, socket) do
    case socket.assigns do
      %{player_id: _} ->
        {:noreply, push_redirect(socket, to: "/sessions/#{socket.assigns.session.uuid}/play")}

      %{session: nil} ->
        {:noreply, push_redirect(socket, to: "/sessions/new", replace: true)}

      _ ->
        {:noreply, socket}
    end
  end
end
