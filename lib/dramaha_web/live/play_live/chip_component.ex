defmodule DramahaWeb.PlayLive.ChipComponent do
  @moduledoc """
  Renders a poker chip that has a different color based on the size
  of the bet / pot
  """

  use DramahaWeb, :live_component

  @impl true
  def render(assigns) do
    ~L"""
      <div class="chip <%= chip_color_class(@size) %>"></div>
    """
  end

  defp chip_color_class(pot_size) do
    cond do
      pot_size < 5 -> "chip--white"
      pot_size < 25 -> "chip--red"
      pot_size < 100 -> "chip--green"
      pot_size < 500 -> "chip--black"
      pot_size < 1000 -> "chip--purple"
      true -> "chip--yellow"
    end
  end
end
