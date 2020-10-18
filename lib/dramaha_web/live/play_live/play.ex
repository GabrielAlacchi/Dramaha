defmodule DramahaWeb.PlayLive.Play do
  @moduledoc """
  LiveView for creating a join form (where a user puts in their username and buy in amount)
  """
  use DramahaWeb, :live_view

  alias Dramaha.Game.Card
  alias Dramaha.Repo
  alias Dramaha.Sessions

  defmodule Context do
    @moduledoc """
    Structure containing context variables used across the tree of components for this live view
    """

    @spec __struct__ :: DramahaWeb.PlayLive.Play.Context.t()
    defstruct selected_cards: []

    @type t() :: %__MODULE__{
            selected_cards: list(Card.card())
          }
  end

  @impl true
  def mount(%{"session_uuid" => uuid}, cookie_session, socket) do
    session = Sessions.get_session_by_uuid(uuid)
    socket = assign(socket, :session, session)

    case cookie_session do
      %{"player_id" => player_id} ->
        player = Repo.get(Dramaha.Sessions.Player, player_id)
        if connected?(socket), do: Sessions.subscribe(session)

        {:ok,
         assign(socket, :player, player)
         |> assign(:page_title, "Play - Dramaha")
         |> assign(:session, session)
         |> assign(:play_context, %Context{})
         |> assign_play_state()}

      _ ->
        {:ok, assign(socket, :player, nil)}
    end
  end

  @impl true
  def handle_params(_, _, socket) do
    case socket.assigns.player do
      nil ->
        {:noreply, push_redirect(socket, to: "/sessions/#{socket.assigns.session.uuid}/join")}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:state_update, socket) do
    {:noreply, assign_play_state(socket)}
  end

  @impl true
  def handle_info(:new_hand, socket) do
    {:noreply,
     assign(socket, :play_context, %Context{})
     |> assign_play_state()}
  end

  @impl true
  def handle_event("select_card", %{"card" => card}, socket) do
    case Card.parse(card) do
      {:invalid_card, _} ->
        {:noreply, socket}

      card ->
        context = socket.assigns.play_context
        updated = %{context | selected_cards: [card | context.selected_cards]}
        {:noreply, assign(socket, :play_context, updated)}
    end
  end

  @impl true
  def handle_event("deselect_card", %{"card" => card}, socket) do
    card = Card.parse(card)

    context = socket.assigns.play_context
    updated = %{context | selected_cards: Enum.filter(context.selected_cards, &(&1 != card))}
    {:noreply, assign(socket, :play_context, updated)}
  end

  defp assign_play_state(socket) do
    state = Sessions.call_gameserver(socket.assigns.session, :query_state)
    # Are we already in the state? If not we need to register ourselves to the session server
    state =
      case Enum.find_index(state.players, fn player ->
             player.player_id == socket.assigns.player.id
           end) do
        nil ->
          Sessions.call_gameserver(socket.assigns.session, {:new_player, socket.assigns.player})

        _ ->
          state
      end

    us = Enum.find(state.players, fn player -> player.player_id == socket.assigns.player.id end)

    assign(socket, :state, state)
    |> assign(:us, us)
  end
end
