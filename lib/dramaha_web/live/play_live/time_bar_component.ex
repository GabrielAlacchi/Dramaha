defmodule DramahaWeb.PlayLive.TimeBarComponent do
  @moduledoc """
  Timer for a player's action timeout
  """

  use DramahaWeb, :live_component

  @impl true
  def render(assigns) do
    ms_left = Process.read_timer(assigns.state.action_timeout_ref)

    ~L"""
    <div id="player-<%= @player.player_id %>-timebar"
         class="player--timebar"
         phx-hook="TimeBar"
         data-expiry-ms="<%= ms_left %>"
         data-duration-seconds="<%= @state.action_timeout_seconds %>">
      <div class="player--timebar-filler"></div>
      <div class="player--timebar-counter">
        <span><%= Integer.floor_div(ms_left, 1000) %></span>
      </div>
    </div>
    """
  end
end
