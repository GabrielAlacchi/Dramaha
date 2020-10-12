defmodule DramahaWeb.PlayLive.ActionBarComponent do
  @moduledoc """
  Action Bar Component
  """
  use DramahaWeb, :live_component

  alias Dramaha.Game.State
  alias Dramaha.Game.Actions
  alias Dramaha.Sessions

  @impl true
  def update(%{state: state, us: us} = assigns, socket) do
    socket =
      cond do
        State.draw_street?(state.current_hand) -> assign(socket, :drawing?, true)
        true -> assign(socket, :drawing?, false)
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:should_display?, should_display?(state, us))
     |> assign_actions(state)}
  end

  defp should_display?(state, us) do
    case state.current_hand do
      nil ->
        false

      hand ->
        State.our_turn?(hand, us.id)
    end
  end

  defp assign_actions(socket, %{current_hand: nil}), do: assign(socket, :available_actions, [])

  defp assign_actions(socket, %{current_hand: %{street: :draw}} = play),
    do: assign_draw_actions(socket, play)

  defp assign_actions(socket, %{current_hand: %{street: :draw_race}} = play),
    do: assign_draw_actions(socket, play)

  defp assign_actions(socket, %{current_hand: state}) do
    available_actions = Actions.available_actions(state)

    non_range_actions = Enum.filter(available_actions, &(!Actions.bet?(&1)))

    call_value =
      case Enum.find(available_actions, fn a -> Actions.atom(a) == :call end) do
        {:call, value} -> value
        _ -> 0
      end

    {socket, actions} =
      case Enum.filter(available_actions, &Actions.bet?(&1)) do
        [{:all_in, size}] ->
          {assign(socket, :bet_range, nil), non_range_actions ++ [{:all_in, size}]}

        [{bet_type, min}, {bet_type_or_all, max}] ->
          middle_bet = Integer.floor_div(min + max, 2)

          socket =
            socket
            |> assign(:bet_range, {min, max})
            |> assign(:middle_action, {bet_type, middle_bet})
            # Is the largest bet all in?
            |> assign(:call_value, call_value)
            |> assign(:bet_so_far, State.current_player(state).bet)
            |> assign(:max_all_in?, bet_type_or_all == :all_in)
            |> assign(:bet_type, bet_type)
            |> assign(:pot_size, state.pot.full_pot + state.pot.committed)

          {socket, non_range_actions}

        _ ->
          {assign(socket, :bet_range, nil), non_range_actions}
      end

    socket
    |> assign(:available_actions, actions)
  end

  defp assign_draw_actions(socket, %{current_hand: state}) do
    {socket, available_actions} =
      case Actions.available_actions(state) do
        [{:draw, []}] ->
          discards = get_discards(socket)

          {
            socket
            |> assign(:draw_action, {:draw, discards}),
            []
          }

        actions ->
          {socket
           |> assign(:draw_action, nil), actions}
      end

    socket
    |> assign(:bet_range, nil)
    |> assign(:available_actions, available_actions)
  end

  @impl true
  def handle_event("action", %{"action-type" => "draw"}, socket) do
    discards = get_discards(socket)

    Sessions.call_gameserver(
      socket.assigns.session,
      {:play_action, socket.assigns.us, {:draw, discards}}
    )

    {:noreply, socket}
  end

  def handle_event("action", params, socket) do
    try do
      action =
        case params do
          %{"action-type" => action, "size" => ""} ->
            String.to_existing_atom(action)

          %{"action-type" => action, "size" => size} ->
            case Integer.parse(size) do
              :error ->
                nil

              {size, _} ->
                {String.to_existing_atom(action), size}
            end
        end

      Sessions.call_gameserver(socket.assigns.session, {:play_action, socket.assigns.us, action})

      {:noreply, socket}
    rescue
      ArgumentError -> {:noreply, socket}
    end
  end

  defp get_discards(socket) do
    state = socket.assigns.state.current_hand
    selected_cards = socket.assigns.play_context.selected_cards
    %{holding: holding} = State.current_player(state)

    holding_list = Tuple.to_list(holding)
    Enum.filter(selected_cards, &Enum.member?(holding_list, &1))
  end
end
