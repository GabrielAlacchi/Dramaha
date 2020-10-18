defmodule DramahaWeb.Components.FormGroupComponent do
  use DramahaWeb, :live_component

  @impl true
  def render(assigns) do
    ~L"""
      <div class="form-group">
        <%= label @form, @key, @label %>
        <%= if assigns[:info] do %>
          <p><%= @info %></p>
        <% end %>
        <%= if assigns[:input_type] == :number do %>
          <%= number_input @form, @key, class: "form-control" %>
        <% else %>
          <%= text_input @form, @key, class: "form-control" %>
        <% end %>
        <div class="error-group">
          <%= error_tag @form, @key %>
        </div>
      </div>
    """
  end
end
