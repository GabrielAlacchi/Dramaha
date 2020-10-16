defmodule Dramaha.Play do
  @moduledoc """
  GenServer which manages the state of a game session
  """
  use GenServer, restart: :transient

  alias Dramaha.Game.State
  alias Dramaha.Game.Actions
  alias Dramaha.Hand
  alias Dramaha.Sessions

  @type call() ::
          :query_state
          | {:new_player, Dramaha.Sessions.Player.t()}
          | {:update_sitout, Dramaha.Sessions.Player.t()}
          | {:configure_session, String.t(), Actions.Config.t()}
          | {:play_action, Dramaha.Sessions.Player.t(), Actions.action()}

  @spec __struct__ :: Dramaha.Play.t()
  defstruct players: [],
            current_hand: nil,
            button_seat: 1,
            uuid: "",
            bet_config: %Actions.Config{small_blind: 1, big_blind: 1}

  @type t() :: %__MODULE__{
          players: list(Dramaha.Game.Player.t()),
          current_hand: State.t() | nil,
          button_seat: Dramaha.Game.Player.seat(),
          uuid: String.t(),
          bet_config: Actions.Config.t()
        }

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

  @spec handle_call(call(), GenServer.from(), t()) :: {:reply, t(), t()} | {:noreply, t()}

  @impl true
  def handle_call(:query_state, _from, play) do
    {:reply, play, play}
  end

  @impl true
  def handle_call({:configure_session, uuid, bet_config}, _from, play) do
    play = %{play | bet_config: bet_config, uuid: uuid}
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
    {:reply, play, play}
  end

  @impl true
  def handle_call({:update_sitout, db_player}, _from, %{players: players} = play) do
    {_, i} =
      Enum.with_index(players)
      |> Enum.filter(fn {player, _} -> player.player_id == db_player.id end)
      |> List.first()

    players =
      List.update_at(players, i, fn player -> %{player | sitting_out: db_player.sitting_out} end)

    play = start_new_hand(%{play | players: players})
    Sessions.broadcast_update(play.uuid)
    {:reply, play, play}
  end

  @impl true
  def handle_call({:play_action, from_player, action}, _from, play) do
    case play.current_hand do
      nil ->
        {:reply, play, play}

      hand ->
        if !State.our_turn?(hand, from_player.id) do
          {:reply, play, play}
        else
          play = play_action(play, action)
          {:reply, play, play}
        end
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
        %{play | current_hand: hand, button_seat: sb.seat}

      length(sitin_players) >= 2 ->
        hand = Dramaha.Hand.start(positioned_by_button, bet_config)
        Sessions.broadcast_update(play.uuid, :new_hand)
        %{play | current_hand: hand}

      true ->
        play
    end
  end

  # This gets called if there's already a hand in progress
  defp start_new_hand(play), do: play

  @spec play_action(t(), Actions.action()) :: t()
  defp play_action(play, action) do
    case Hand.play_action(play.current_hand, action) do
      {:ok, state} ->
        play = %{play | current_hand: state}
        play = maybe_deal(play)

        case maybe_showdown(play) do
          {_, play} ->
            Sessions.broadcast_update(play.uuid)
            play
        end

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
    case play.current_hand do
      %{street: :showdown} ->
        case maybe_showdown(play) do
          {:done, play} ->
            play = end_hand(play)
            Sessions.broadcast_update(play.uuid)
            {:noreply, play}

          {_, play} ->
            {:noreply, play}
        end

      _ ->
        {:noreply, play}
    end
  end

  def handle_info(:next_hand, play) do
    {:noreply, end_hand(play)}
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

    start_new_hand(%{play | button_seat: next_btn.seat, current_hand: nil})
  end

  @spec maybe_deal(t()) :: t()
  defp maybe_deal(%{current_hand: %{awaiting_deal: true}} = play) do
    timeout =
      cond do
        State.racing?(play.current_hand) && play.current_hand.street != :preflop_race ->
          2500

        true ->
          650
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
        Process.send_after(self(), :next_showdown, 2500)
        {:showdown, %{play | current_hand: hand}}

      :no_more_pots ->
        {:done, play}
    end
  end

  defp maybe_showdown(%{current_hand: %{street: :folded}} = play) do
    Process.send_after(self(), :next_hand, 2500)
    {:done, play}
  end

  defp maybe_showdown(play), do: {:ignore, play}
end
