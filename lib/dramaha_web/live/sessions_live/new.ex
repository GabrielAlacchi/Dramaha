defmodule DramahaWeb.SessionsLive.New do
  use DramahaWeb, :live_view

  @impl true
  def mount(_params, _live_session, socket) do
    {:ok, socket}
  end
end
