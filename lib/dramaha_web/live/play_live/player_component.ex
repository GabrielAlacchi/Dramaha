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
        %{holding: holding, player_id: id, faceup_card: faceup, show_hand: show_hand}
        when holding != nil ->
          if is_us || show_hand do
            cards = Tuple.to_list(holding) |> Enum.map(&{&1, false})

            selectable? =
              State.draw_street?(state.current_hand) && State.our_turn?(state.current_hand, id)

            {assign(socket, :selectable?, selectable?), cards}
          else
            cards = Tuple.to_list(holding)

            {assign(socket, :selectable?, false),
             Enum.map(cards, fn card ->
               if card == faceup do
                 {card, false}
               else
                 {nil, true}
               end
             end)}
          end

        _ ->
          {assign(socket, :selectable?, false), []}
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
end
