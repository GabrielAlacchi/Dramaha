defmodule DramahaWeb.SessionsLive.Join do
  @moduledoc """
  LiveView for creating a join form (where a user puts in their username and buy in amount)
  """
  use DramahaWeb, :live_view

  alias Dramaha.Sessions
  alias Dramaha.Sessions.Player
  alias Dramaha.Repo

  @impl true
  def mount(%{"session_uuid" => uuid} = params, live_session, socket) do
    socket =
      case live_session do
        # This will lead to a redirect in handle_params
        %{"player_id" => player_id} ->
          socket |> assign(:player, Repo.get(Player, player_id))

        _ ->
          socket
      end

    session = Sessions.get_session_by_uuid(uuid)

    {:ok,
     socket
     |> assign(:session, session)
     |> assign(:current_session, nil)
     |> assign(:page_title, "Join a Session - Dramaha")
     |> assign(:global_error, Map.get(params, "global_error"))
     |> assign_join_changeset(params)}
  end

  @impl true
  def handle_params(_params, _, socket) do
    case socket.assigns do
      %{player: p} when p != nil ->
        session = Repo.get(Sessions.Session, p.session_id)
        {:noreply, assign(socket, :current_session, session)}

      %{session: nil} ->
        {:noreply, push_redirect(socket, to: "/sessions/new", replace: true)}

      _ ->
        {:noreply, socket}
    end
  end

  defp assign_join_changeset(socket, params) do
    attrs = Map.take(params, ["display_name", "current_stack"])

    changeset =
      Sessions.join_session_changeset(socket.assigns.session, attrs)
      |> Map.put(:action, :validate)

    changeset =
      cond do
        Map.has_key?(params, "name_taken") && params["name_taken"] == "true" ->
          changeset
          |> Ecto.Changeset.add_error(:display_name, "This display name is already in use")

        true ->
          changeset
      end

    socket
    |> assign(:changeset, changeset)
  end
end
