defmodule Dramaha.Replay do
  @moduledoc """
  Functions related to persisting session data (in the future replaying hands will be supported)
  """
  alias Dramaha.Sessions.Player

  import Ecto.Query, warn: false
  alias Dramaha.Repo

  @spec persist_session_data(Dramaha.Play.t()) :: any()
  def persist_session_data(play) do
    Repo.transaction(fn ->
      Enum.each(play.players, fn player ->
        from(p in Player,
          where: p.id == ^player.player_id,
          update: [set: [current_stack: ^player.stack, sitting_out: ^player.sitting_out]]
        )
        |> Repo.update_all([])
      end)
    end)
  end
end
