defmodule DramahaWeb.PlayLive.PlayerComponent do
  @moduledoc """
  Live Component representing a player's stack, hand and other info
  """
  use DramahaWeb, :live_component

  alias Dramaha.Game.State

  def update(%{state: state, player: player, is_us: is_us} = assigns, socket) do
    hand_state_player =
      case state.current_hand do
        nil ->
          nil

        %{players: players} ->
          Enum.find(players, fn %{player_id: id} -> id == player.player_id end)
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:hand_state_player, hand_state_player)
     |> assign(:sitting_out?, player.sitting_out)
     |> assign_turn(state, player)
     |> assign_stack(player, hand_state_player)
     |> assign_cards(state, hand_state_player, is_us)
     |> assign_action(hand_state_player)}
  end

  defp assign_turn(socket, state, player) do
    our_turn? =
      case state.current_hand do
        nil -> false
        hand -> State.our_turn?(hand, player.player_id)
      end

    assign(socket, :turn?, our_turn?)
  end

  defp assign_stack(socket, player, hand_state_player) do
    current_stack =
      case hand_state_player do
        nil ->
          player.stack

        # If we're in a hand the correct pot size will come from the player's stack in the hand state
        hsp ->
          hsp.stack
      end

    assign(socket, :stack, current_stack)
  end

  defp assign_cards(socket, state, hand_state_player, is_us) do
    {socket, cards} =
      case hand_state_player do
        %{
          holding: holding,
          dealt_cards: dealt_cards,
          faceup_card: faceup_card,
          show_hand: show_hand
        }
        when holding != nil ->
          {socket, cards} =
            if is_us || show_hand do
              cards = dealt_cards |> Enum.map(&{&1, false})

              selectable? = State.draw_street?(state.current_hand)

              {assign(socket, :selectable?, selectable?), cards}
            else
              {assign(socket, :selectable?, false),
               Enum.map(dealt_cards, fn card ->
                 if card == faceup_card do
                   {card, false}
                 else
                   {nil, true}
                 end
               end)}
            end

          {socket |> assign(:faceup_card, faceup_card) |> assign(:folded, false), cards}

        %{dealt_cards: dealt_cards} ->
          {
            assign(socket, :selectable?, false)
            |> assign(:folded, true)
            |> assign(:faceup_card, nil),
            Enum.map(dealt_cards, &{&1, !is_us})
          }

        nil ->
          {assign(socket, :selectable?, false)
           |> assign(:faceup_card, nil)
           |> assign(:folded, true), []}
      end

    assign(socket, :cards, cards)
  end

  defp assign_action(socket, hand_state_player) do
    action =
      case hand_state_player do
        nil -> nil
        hsp -> hsp.last_street_action
      end

    assign(socket, :action, action)
  end

  @impl true
  def handle_event("is_us", _, socket) do
  end
end
