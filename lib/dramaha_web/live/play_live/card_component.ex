defmodule DramahaWeb.PlayLive.CardComponent do
  use DramahaWeb, :live_component

  alias Dramaha.Game.Card

  def update(assigns, socket) do
    assigns =
      assigns
      |> put_default(:selected?, false)
      |> put_default(:selectable?, false)

    {:ok,
     socket
     |> assign(assigns)}
  end

  defp put_default(assigns, key, value) do
    if !Map.has_key?(assigns, key) do
      Map.put(assigns, key, value)
    else
      assigns
    end
  end
end
