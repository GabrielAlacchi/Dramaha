defmodule DramahaWeb.PlayLive.ActionComponent do
  @moduledoc """
  The bar which appears when an action is played
  """
  use DramahaWeb, :live_component

  alias Dramaha.Game.Actions

  @impl true
  def render(assigns) do
    ~L"""
    <div class="player--action <%= action_class(@action) %>">
      <%= Actions.describe(@action) %>
    </div>
    """
  end

  @spec action_class(Actions.action()) :: String.t()
  def action_class(action) do
    cond do
      Actions.bet?(action) ->
        "aggressive"

      true ->
        case action do
          {:call, _} -> "call"
          _ -> "passive"
        end
    end
  end
end
