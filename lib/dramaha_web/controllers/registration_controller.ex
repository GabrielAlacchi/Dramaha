defmodule DramahaWeb.RegistrationController do
  use DramahaWeb, :controller

  alias DramahaWeb.Router.Helpers, as: Routes
  alias Dramaha.Sessions

  def register(conn, %{"session_uuid" => uuid, "player" => player_attrs}) do
    case Sessions.get_session_by_uuid(uuid) do
      nil ->
        conn |> redirect(to: "/sessions/new")

      session ->
        current_session_uuid = get_session(conn, "session_uuid")
        current_player_id = get_session(conn, "player_id")

        case Sessions.join_session(session, player_attrs) do
          {:ok, player} ->
            conn =
              put_session(conn, :session_uuid, session.uuid) |> put_session(:player_id, player.id)

            # Tell the old session that the play has quit
            if current_session_uuid != nil do
              Sessions.cast_gameserver(
                Sessions.get_session_by_uuid(current_session_uuid),
                {:quit, current_player_id}
              )
            end

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

          {:no_space, message} ->
            redirect(conn,
              to:
                Routes.live_path(conn, DramahaWeb.SessionsLive.Join, uuid,
                  display_name: player_attrs["display_name"],
                  current_stack: player_attrs["current_stack"],
                  global_error: message
                )
            )
        end
    end
  end

  @spec quit(Plug.Conn.t(), any) :: Plug.Conn.t()
  def quit(conn, _) do
    configure_session(conn, drop: true)
    |> redirect(to: "/sessions/new")
  end
end
