defmodule DramahaWeb.ActionLogLive.LogEntryComponent do
  @moduledoc """
  A log entry object
  """
  use DramahaWeb, :live_component

  @impl true
  def render(assigns) do
    ~L"""
      <li class="log--entry">
        <span><%= @log_entry.emitted_by %>: </span>
        <span><%= @log_entry.message %></span>
      </li>
    """
  end
end
