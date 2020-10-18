defmodule DramahaWeb.SessionsLive.New do
  use DramahaWeb, :live_view

  alias DramahaWeb.Router.Helpers, as: Routes
  alias Dramaha.Repo

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

          %{uuid: uuid} ->
            to = Routes.live_path(DramahaWeb.Endpoint, DramahaWeb.PlayLive.Play, uuid)
            {:noreply, push_redirect(socket, to: to)}
        end
    end
  end
end
