defmodule DramahaWeb.SessionsLive.New do
  use DramahaWeb, :live_view

  alias DramahaWeb.Router.Helpers, as: Routes
  alias Dramaha.{Repo, Sessions}

  @impl true
  def mount(_params, live_session, socket) do
    socket =
      case live_session do
        %{"player_id" => id} ->
          player = Repo.get(Dramaha.Sessions.Player, id)
          assign(socket, :player, player)

        _ ->
          assign(socket, :player, nil)
      end

    {:ok,
     socket
     |> assign(:current_session, nil)
     |> assign(:page_title, "Start a New Session - Dramaha")}
  end

  @impl true
  def handle_params(_params, _, socket) do
    case socket.assigns.player do
      nil ->
        {:noreply, socket}

      %{session_id: session_id} ->
        case Repo.get(Dramaha.Sessions.Session, session_id) do
          nil ->
            {:noreply, socket}

          current_session ->
            {:noreply, assign(socket, :current_session, current_session)}
        end
    end
  end
end
