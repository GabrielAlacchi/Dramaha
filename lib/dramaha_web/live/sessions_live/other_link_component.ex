defmodule DramahaWeb.SessionsLive.OtherLinkComponent do
  @moduledoc """
  Component encapsulating a link to another session
  """
  use DramahaWeb, :live_component

  alias DramahaWeb.Router.Helpers, as: Routes

  @impl true
  def update(%{player: player, session: session} = assigns, socket) do
    {:ok, last_played} = player.updated_at |> Timex.format("{relative}", :relative)

    rejoin_link = Routes.live_path(DramahaWeb.Endpoint, DramahaWeb.PlayLive.Play, session.uuid)

    {:ok,
     assign(socket, assigns)
     |> assign(:last_played, last_played)
     |> assign(:rejoin_link, rejoin_link)}
  end

  @impl true
  def render(assigns) do
    ~L"""
    <div class="other-link">
      <p>You're currently registered as <strong><%= @player.display_name %></strong> in another game session which you played in <%= @last_played %>.</p>
      <p>If you'd like to rejoin that session <%= link("click here", to: @rejoin_link) %>.</p>
    </div>
    """
  end
end
