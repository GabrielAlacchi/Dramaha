defmodule DramahaWeb.PageLive do
  use DramahaWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, query: "", results: %{})}
  end

  @impl true
  def handle_params(_, _, socket) do
    {:noreply, push_redirect(socket, to: "/sessions/new")}
  end
end
