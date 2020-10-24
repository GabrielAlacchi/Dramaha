defmodule DramahaWeb.PlayLive.BottomPanelComponent do
  @moduledoc """
  The bottom bar of the UI where the action bar and current hands
  are found
  """

  use DramahaWeb, :live_component

  @impl true
  def render(assigns) do
    ~L"""
    <section class="bottom-panel">
      <%= live_render(@socket, DramahaWeb.ActionLogLive.Log, id: :log_view, session: %{"session" => @session}) %>
      <%= live_component(@socket, DramahaWeb.PlayLive.ActionBarComponent, id: :action_bar, session: @session, play_context: @play_context, state: @state, us: @us) %>
      <%= live_component(@socket, DramahaWeb.PlayLive.CurrentHandComponent, id: :current_hand, state: @state, us: @us) %>
    </section>
    """
  end
end
