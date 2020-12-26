defmodule Dramaha.Play do
  @moduledoc """
  GenServer which manages the state of a game session
  """
  use GenServer, restart: :transient
  require Logger

  alias Dramaha.Replay
  alias Dramaha.Game.{State, Actions, Showdown}
  alias Dramaha.Hand
  alias Dramaha.Sessions

  @type addon() :: {integer(), integer()}

  @type call() ::
          :query_state
          | {:new_player, Dramaha.Sessions.Player.t()}
          | {:update_sitout, integer(), boolean()}
          | {:configure_session, String.t(), Actions.Config.t(), integer()}
          | {:play_action, Dramaha.Game.Player.t(), Actions.action()}
          | {:add_on, integer(), integer()}
          | {:quit, integer()}
          | {:has_player_quit?, integer()}

  @type cast() :: {:quit, integer()}

  @spec __struct__ :: Dramaha.Play.t()
  defstruct players: [],
            current_hand: nil,
            button_seat: 1,
            uuid: "",
            max_buy_in: 0,
            bet_config: %Actions.Config{small_blind: 1, big_blind: 1},
            action_timeout_ref: nil,
            action_timeout_stamp: nil,
            action_timeout_seconds: nil,
            pending_addons: [],
            pending_quits: []

  @type t() :: %__MODULE__{
          players: list(Dramaha.Game.Player.t()),
          current_hand: State.t() | nil,
          button_seat: Dramaha.Game.Player.seat(),
          uuid: String.t(),
          max_buy_in: integer(),
          bet_config: Actions.Config.t(),
          action_timeout_ref: non_neg_integer() | nil,
          action_timeout_stamp: DateTime.t() | nil,
          action_timeout_seconds: integer() | nil,
          pending_addons: list(addon()),
          pending_quits: list({integer(), DateTime.t()})
        }

  def lookup_suffix do
    ""
  end

  def configuration_messages(session) do
    bet_config = %Dramaha.Game.Actions.Config{
      small_blind: session.small_blind,
      big_blind: session.big_blind
    }

    [{:call, {:configure_session, session.uuid, bet_config, session.max_buy_in}}]
  end

  @spec start_link([
          {:debug, [:log | :statistics | :trace | {any, any}]}
          | {:hibernate_after, :infinity | non_neg_integer}
          | {:name, atom | {:global, any} | {:via, atom, any}}
          | {:spawn_opt,
             :link
             | :monitor
             | {:fullsweep_after, non_neg_integer}
             | {:min_bin_vheap_size, non_neg_integer}
             | {:min_heap_size, non_neg_integer}
             | {:priority, :high | :low | :normal}}
          | {:timeout, :infinity | non_neg_integer}
        ]) :: :ignore | {:error, any} | {:ok, pid}
  def start_link(options) do
    GenServer.start_link(__MODULE__, %Dramaha.Play{}, options)
  end

  @impl true
  @spec init(t()) :: {:ok, t()}
  def init(play) do
    {:ok, play}
  end

  @spec handle_call(call(), GenServer.from(), t()) ::
          {:reply, t(), t()} | {:reply, boolean(), t()} | {:noreply, t()}

  @impl true
  def handle_call(:query_state, _from, play) do
    {:reply, play, play}
  end

  @impl true
  def handle_call({:configure_session, uuid, bet_config, max_buy_in}, _from, play) do
    play = %{play | bet_config: bet_config, uuid: uuid, max_buy_in: max_buy_in}
    {:reply, play, play}
  end

  @impl true
  def handle_call({:new_player, new_player}, _from, %{players: players} = play) do
    # Players list should be sorted by seat ascending
    players_after =
      Enum.with_index(players) |> Enum.filter(fn {player, _} -> player.seat > new_player.seat end)

    new_game_player = %Dramaha.Game.Player{
      player_id: new_player.id,
      name: new_player.display_name,
      seat: new_player.seat,
      stack: new_player.current_stack,
      sitting_out: new_player.sitting_out
    }

    players =
      case players_after do
        [] -> players ++ [new_game_player]
        [{_, i} | _] -> List.insert_at(players, i, new_game_player)
      end

    # Call start_new_hand here incase adding this player makes the game playable
    play = start_new_hand(%{play | players: players})
    Sessions.broadcast_update(play.uuid)

    Sessions.cast_log_event(
      play.uuid,
      "#{new_player.display_name} has joined the game.",
      "Server"
    )

    Sessions.update_leaderboard(play.uuid)

    {:reply, play, play}
  end

  @impl true
  def handle_call({:update_sitout, player_id, sitting_out}, _from, play) do
    play = handle_sitout(play, player_id, sitting_out)
    {:reply, play, play}
  end

  @impl true
  def handle_call({:play_action, from_player, action}, _from, play) do
    case play.current_hand do
      nil ->
        {:reply, play, play}

      hand ->
        if !State.our_turn?(hand, from_player.player_id) do
          {:reply, play, play}
        else
          play = play_action(play, action)
          {:reply, play, play}
        end
    end
  end

  @impl true
  def handle_call({:add_on, player_id, addon_chips}, _from, play) do
    cond do
      play.current_hand != nil && State.in_hand?(play.current_hand, player_id) ->
        play = merge_addon(play, {player_id, addon_chips})
        {:reply, play, play}

      true ->
        play = apply_addon(play, {player_id, addon_chips})
        Sessions.broadcast_update(play.uuid)
        {:reply, play, play}
    end
  end

  @impl true
  def handle_call({:has_player_quit?, player_id}, _from, play) do
    player = Enum.find(play.players, &(player_id == &1.player_id))
    pending_quit = Enum.find(play.pending_quits, fn {id, _} -> id == player_id end)

    if pending_quit == nil && player != nil do
      {:reply, false, play}
    else
      {:reply, true, play}
    end
  end

  @impl true
  @spec handle_cast(cast(), t()) :: {:noreply, t()}
  def handle_cast({:quit, player_id}, play) do
    play = handle_sitout(play, player_id, true)

    Sessions.broadcast_update(play.uuid, {:player_quit, player_id})

    cond do
      play.current_hand != nil && State.in_hand?(play.current_hand, player_id) ->
        {:noreply,
         %{play | pending_quits: [{player_id, DateTime.utc_now()} | play.pending_quits]}}

      true ->
        play = handle_player_quit(play, {player_id, DateTime.utc_now()})
        Sessions.broadcast_update(play.uuid)
        {:noreply, play}
    end
  end

  @spec start_new_hand(t()) :: t()
  defp start_new_hand(%{current_hand: nil, bet_config: bet_config} = play) do
    sitin_players = Enum.filter(play.players, &(!&1.sitting_out && &1.stack > 0))

    positioned_by_button =
      Enum.sort_by(sitin_players, fn player ->
        {player.seat <= play.button_seat, player.seat}
      end)

    btn_on_player? = Enum.any?(positioned_by_button, &(&1.seat == play.button_seat))

    cond do
      # If just 2 players are in the session and the button isn't on one of them then
      # move the button to the next small blind
      length(sitin_players) == 2 && !btn_on_player? ->
        [sb, bb] = positioned_by_button
        hand = Dramaha.Hand.start([bb, sb], bet_config)
        Sessions.broadcast_update(play.uuid, :new_hand)

        Sessions.cast_log_event(
          play.uuid,
          "Dealing a new hand.",
          "Dealer"
        )

        action_timeout(%{play | current_hand: hand, button_seat: sb.seat})

      length(sitin_players) >= 2 ->
        hand = Dramaha.Hand.start(positioned_by_button, bet_config)
        Sessions.broadcast_update(play.uuid, :new_hand)

        Sessions.cast_log_event(
          play.uuid,
          "Dealing a new hand.",
          "Dealer"
        )

        action_timeout(%{play | current_hand: hand})

      true ->
        Sessions.broadcast_update(play.uuid)

        Sessions.cast_log_event(
          play.uuid,
          "Waiting for more players to start a new hand.",
          "Player"
        )

        play
    end
  end

  # This gets called if there's already a hand in progress
  defp start_new_hand(play), do: play

  @spec play_action(t(), Actions.action()) :: t()
  defp play_action(play, action) do
    log_action(play, action)

    case Hand.play_action(play.current_hand, action) do
      {:ok, state} ->
        play = clear_action_timeout(%{play | current_hand: state})

        play =
          case state do
            %{awaiting_deal: true} ->
              maybe_deal(play)

            %{street: street} when street == :showdown or street == :folded ->
              {_, play} = maybe_showdown(play)
              play

            _ ->
              if State.current_player(state).sitting_out do
                play_action(play, Actions.default_action(state))
              else
                action_timeout(play)
              end
          end

        Sessions.broadcast_update(play.uuid)

        play

      {:invalid_action, _} ->
        play
    end
  end

  @impl true
  def handle_info(:deal_timeout, play) do
    case play.current_hand do
      %{awaiting_deal: true} ->
        {:noreply, play_action(play, :deal)}

      _ ->
        {:noreply, play}
    end
  end

  def handle_info(:next_showdown, play) do
    Logger.info("Handling next showdown")

    case play.current_hand do
      %{street: :showdown} ->
        case maybe_showdown(play) do
          {:done, play} ->
            play = end_hand(play)
            Sessions.broadcast_update(play.uuid)
            {:noreply, play}

          {_, play} ->
            Sessions.broadcast_update(play.uuid)
            {:noreply, play}
        end

      _ ->
        {:noreply, play}
    end
  end

  def handle_info(:next_hand, play) do
    {:noreply, end_hand(play)}
  end

  def handle_info({:action_timeout, timed_out_id}, play) do
    player_idx = play.current_hand.player_turn
    current_player = State.current_player(play.current_hand)

    # Check for a stale timeout (one that fired while processing the action of a player).
    if timed_out_id == current_player.player_id do
      Logger.info("[Dramaha.Play] Action timeout for Seat #{current_player.seat}")

      # Set the player's status to sitting out
      updated_hand_state = %{
        play.current_hand
        | players:
            List.update_at(play.current_hand.players, player_idx, &%{&1 | sitting_out: true})
      }

      sess_player_idx = Enum.find_index(play.players, &(&1.player_id == current_player.player_id))

      updated_session_players =
        List.update_at(play.players, sess_player_idx, &%{&1 | sitting_out: true})

      play = %{play | current_hand: updated_hand_state, players: updated_session_players}
      play = play_action(play, Actions.default_action(play.current_hand))

      {:noreply, play}
    else
      # If we have a stale timeout
      {:noreply, play}
    end
  end

  @spec end_hand(t()) :: t()
  defp end_hand(play) do
    players =
      Enum.map(play.players, fn player ->
        hand_state_player =
          Enum.find(play.current_hand.players, fn %{player_id: pid} -> pid == player.player_id end)

        case hand_state_player do
          nil ->
            player

          hsp ->
            %{player | stack: hsp.stack}
        end
      end)

    play = %{play | players: players}

    # Find the first player sitting in which has a seat > current_btn
    sitting_in = Enum.filter(play.players, &(!&1.sitting_out))
    next_btn = Enum.find(sitting_in, &(&1.seat > play.button_seat))

    next_btn = next_btn || Enum.find(sitting_in, &(&1.seat > play.button_seat - 6))
    next_btn = next_btn || %{seat: play.button_seat}

    post_addons = Enum.reduce(play.pending_addons, play, &apply_addon(&2, &1))
    post_quits = Enum.reduce(play.pending_quits, post_addons, &handle_player_quit(&2, &1))

    new_play =
      start_new_hand(%{
        post_quits
        | button_seat: next_btn.seat,
          pending_addons: [],
          current_hand: nil
      })

    # Persist things from after addons
    Task.start(fn ->
      Replay.persist_session_data(post_addons)
    end)

    Sessions.update_leaderboard(play.uuid)

    new_play
  end

  @spec maybe_deal(t()) :: t()
  defp maybe_deal(%{current_hand: %{awaiting_deal: true}} = play) do
    timeout =
      cond do
        State.racing?(play.current_hand) && play.current_hand.street != :preflop_race ->
          2500

        true ->
          1200
      end

    Process.send_after(self(), :deal_timeout, timeout)
    play
  end

  defp maybe_deal(play) do
    play
  end

  @spec maybe_showdown(t()) :: {:showdown, t()} | {:done, t()} | {:ignore, t()}
  defp maybe_showdown(%{current_hand: %{street: :showdown}} = play) do
    case Hand.handle_next_showdown(play.current_hand) do
      {:ok, hand} ->
        Process.send_after(self(), :next_showdown, 10000)

        {:showdown, log_last_showdown(%{play | current_hand: hand})}

      :no_more_pots ->
        {:done, play}
    end
  end

  defp maybe_showdown(%{current_hand: %{street: :folded}} = play) do
    Process.send_after(self(), :next_hand, 1500)
    {:done, log_last_showdown(play)}
  end

  defp maybe_showdown(play), do: {:ignore, play}

  @spec action_timeout(t()) :: t()
  def action_timeout(%{current_hand: nil} = play), do: play

  def action_timeout(%{current_hand: hand} = play) do
    current_player = State.current_player(hand)

    seconds_timeout =
      case hand.street do
        :flop -> 30
        :turn -> 50
        :river -> 80
        _ -> 20
      end

    timer_ref =
      Process.send_after(
        self(),
        {:action_timeout, current_player.player_id},
        seconds_timeout * 1000
      )

    time_left = Process.read_timer(timer_ref)

    expire_timestamp =
      DateTime.utc_now()
      |> DateTime.add(time_left, :millisecond)

    %{
      play
      | action_timeout_ref: timer_ref,
        action_timeout_stamp: expire_timestamp,
        action_timeout_seconds: seconds_timeout
    }
  end

  @spec clear_action_timeout(t()) :: t()
  def clear_action_timeout(%{action_timeout_ref: nil} = play), do: play

  def clear_action_timeout(play) do
    Process.cancel_timer(play.action_timeout_ref)
    %{play | action_timeout_ref: nil, action_timeout_stamp: nil, action_timeout_seconds: nil}
  end

  @spec apply_addon(t(), addon()) :: t()
  def apply_addon(play, {player_id, chips}) do
    player_index = Enum.find_index(play.players, &(&1.player_id == player_id))
    player = Enum.at(play.players, player_index)

    {updated_players, stack_increase} =
      if player_index != nil do
        # Don't add on past the maximum chips
        updated_stack = min(max(player.stack, play.max_buy_in), player.stack + chips)
        updated_player = %{player | stack: updated_stack}

        {
          List.replace_at(play.players, player_index, updated_player),
          updated_player.stack - player.stack
        }
      else
        {play.players, 0}
      end

    if stack_increase > 0 &&
         Sessions.update_player_stack(player_id, player.stack + stack_increase, stack_increase) do
      %{play | players: updated_players}
    else
      play
    end
  end

  @spec merge_addon(t(), addon()) :: t()
  def merge_addon(play, {player_id, chips}) do
    index = Enum.find_index(play.pending_addons, fn {id, _} -> id == player_id end)

    if index == nil do
      %{play | pending_addons: [{player_id, chips} | play.pending_addons]}
    else
      %{
        play
        | pending_addons:
            List.update_at(play.pending_addons, index, fn {_, current_chips} ->
              {player_id, current_chips + chips}
            end)
      }
    end
  end

  @spec handle_sitout(t(), integer(), boolean()) :: t()
  defp handle_sitout(%{players: players} = play, player_id, sitting_out) do
    i = Enum.find_index(players, &(&1.player_id == player_id))

    cond do
      i == nil ->
        play

      true ->
        players =
          List.update_at(players, i, fn player -> %{player | sitting_out: sitting_out} end)

        play = %{play | players: players}

        play =
          case play.current_hand do
            nil ->
              start_new_hand(play)

            hand ->
              hsp_index =
                Enum.find_index(hand.players, fn %{player_id: id} -> id == player_id end)

              updated_hand =
                cond do
                  hsp_index != nil ->
                    updated_players =
                      List.update_at(hand.players, hsp_index, &%{&1 | sitting_out: sitting_out})

                    %{hand | players: updated_players}

                  true ->
                    hand
                end

              if State.current_player(updated_hand).player_id == player_id do
                play_action(
                  %{play | current_hand: updated_hand},
                  Actions.default_action(updated_hand)
                )
              else
                %{play | current_hand: updated_hand}
              end
          end

        Task.start(fn ->
          Sessions.update_player_sitout(player_id, sitting_out)
        end)

        Sessions.broadcast_update(play.uuid)
        play
    end
  end

  @spec handle_player_quit(t(), {integer(), DateTime.t()}) :: t()
  defp handle_player_quit(play, {player_id, quit_at}) do
    Task.start(fn -> Sessions.player_quit(player_id, quit_at) end)

    quitting_player = Enum.find(play.players, &(&1.player_id == player_id))

    if quitting_player != nil do
      Sessions.cast_log_event(play.uuid, "#{quitting_player.name} has quit the game", "Server")
    end

    Sessions.broadcast_update(play.uuid)
    %{play | players: Enum.filter(play.players, &(&1.player_id != player_id))}
  end

  @spec log_action(t(), Actions.action()) :: :ok
  defp log_action(_, :deal), do: :ok

  defp log_action(play, action) do
    current_player = State.current_player(play.current_hand)

    description = "#{Actions.describe(action)}."

    Sessions.cast_log_event(play.uuid, description, current_player.name)
  end

  @spec log_last_showdown(t()) :: t()
  defp log_last_showdown(%{current_hand: nil} = play), do: play
  defp log_last_showdown(%{current_hand: %{showdowns: []}} = play), do: play

  defp log_last_showdown(%{current_hand: hand} = play) do
    last_showdown = List.last(hand.showdowns)

    Showdown.describe(last_showdown)
    |> Enum.each(&Sessions.cast_log_event(play.uuid, &1, "Server"))

    play
  end
end
