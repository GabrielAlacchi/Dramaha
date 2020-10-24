defmodule DramahaWeb.ActionLogLive.Log do
  @moduledoc """
  Live view which displays the game log for a session
  """
  @retain_total 500

  use DramahaWeb, :live_view

  alias Dramaha.Sessions

  @impl true
  def mount(:not_mounted_at_router, %{"session" => session}, socket) do
    if connected?(socket) do
      Sessions.subscribe_to_logs(session.uuid)
    end

    new_events = Sessions.getn_log_events(session.uuid, 100)

    {:ok,
     assign(socket, :session, session)
     |> assign(:log_events, [])
     |> assign_new_events(new_events)}
  end

  @impl true
  def handle_info({:log_event, log_event}, socket) do
    {:noreply, assign_new_events(socket, [log_event])}
  end

  defp assign_new_events(socket, new_events) do
    current_events = socket.assigns.log_events

    updated_events = Itertools.merge_by(current_events, new_events, & &1.sequence)

    updated_events =
      if length(updated_events) > @retain_total do
        Enum.drop(updated_events, length(updated_events) - @retain_total)
      else
        updated_events
      end

    assign(socket, :log_events, updated_events)
  end
end
