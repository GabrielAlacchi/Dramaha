defmodule DramahaWeb.SessionsLive.FormComponent do
  use DramahaWeb, :live_component
  alias Dramaha.Sessions
  alias DramahaWeb.Router.Helpers, as: Routes

  @impl true
  def update(%{session: session} = assigns, socket) do
    changeset = Sessions.change_session(session)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:changeset, changeset)}
  end

  @impl true
  def handle_event("validate", %{"session" => session_params}, socket) do
    changeset =
      socket.assigns.session
      |> Sessions.change_session(session_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("create", %{"session" => session_params}, socket) do
    case Sessions.create_session(session_params) do
      {:ok, session} ->
        redirect_to =
          Routes.live_path(DramahaWeb.Endpoint, DramahaWeb.SessionsLive.Join, session.uuid)

        {:noreply, redirect(socket, to: redirect_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end
end
