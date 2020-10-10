defmodule DramahaWeb.RegistrationController do
  use DramahaWeb, :controller

  alias Dramaha.Sessions

  def register(conn, %{"session_uuid" => uuid, "player" => player_attrs}) do
    case Sessions.get_session_by_uuid(uuid) do
      nil ->
        conn |> redirect(to: "/sessions/new")

      session ->
        case Sessions.join_session(session, player_attrs) do
          {:ok, player} ->
            conn =
              put_session(conn, :session_uuid, session.uuid) |> put_session(:player_id, player.id)

            redirect(conn, to: "/sessions/#{uuid}/play")
        end
    end
  end
end
