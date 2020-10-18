defmodule DramahaWeb.RegistrationController do
  use DramahaWeb, :controller

  alias DramahaWeb.Router.Helpers, as: Routes
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

          {:error, changeset} ->
            redirect(conn,
              to:
                Routes.live_path(conn, DramahaWeb.SessionsLive.Join, uuid,
                  display_name: player_attrs["display_name"],
                  current_stack: player_attrs["current_stack"],
                  name_taken: Keyword.has_key?(changeset.errors, :session_id)
                )
            )
        end
    end
  end
end
