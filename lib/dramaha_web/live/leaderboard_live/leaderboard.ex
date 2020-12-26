defmodule DramahaWeb.LeaderboardLive.Leaderboard do
  use DramahaWeb, :live_view

  alias Dramaha.Sessions

  @impl true
  def mount(:not_mounted_at_router, %{"session" => session}, socket) do
    if connected?(socket) do
      Sessions.subscribe_to_leaderboard(session.uuid)
    end

    leaderboard = Sessions.get_leaderboard(session.uuid)

    {:ok,
     assign(socket, :session, session)
     |> assign(:entries, leaderboard.entries)}
  end

  @impl true
  def handle_info({:leaderboard_update, entries}, socket) do
    {:noreply, assign(socket, :entries, entries)}
  end

  defp chips_won_format(chips_won) do
    cond do
      chips_won > 0 ->
        "+#{chips_won}"

      true ->
        "#{chips_won}"
    end
  end
end
