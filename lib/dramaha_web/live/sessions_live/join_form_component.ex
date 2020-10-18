defmodule DramahaWeb.SessionsLive.JoinFormComponent do
  use DramahaWeb, :live_component
  alias Dramaha.Sessions

  @impl true
  def handle_event("validate", %{"player" => player_attrs}, socket) do
    changeset =
      socket.assigns.session
      |> Sessions.join_session_changeset(player_attrs)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end
end
