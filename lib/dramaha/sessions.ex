defmodule Dramaha.Sessions do
  @moduledoc """
  The sessions context.
  """

  import Ecto.Query, warn: false
  alias Ecto.Multi
  alias Dramaha.Repo
  alias Dramaha.Sessions.BuyIn
  alias Dramaha.Sessions.Player
  alias Dramaha.Sessions.Session

  @type game_proc_type :: Dramaha.Play | Dramaha.ActionLogger | Dramaha.Leaderboard

  def get_session_by_uuid(uuid), do: Repo.get_by(Session, uuid: uuid)

  def create_session(attrs) do
    session_changeset =
      %Session{uuid: UUID.uuid4()}
      |> Session.changeset(attrs)

    multi =
      Multi.new()
      |> Multi.insert(:session, session_changeset)
      |> Multi.run(:configure_server, fn _, %{session: session} ->
        {:ok, configure_gameserver(session)}
      end)

    case Repo.transaction(multi) do
      {:ok, %{session: session}} ->
        {:ok, session}

      {:error, :session, changeset, _} ->
        {:error, changeset}
    end
  end

  def change_session(%Session{} = session, attrs \\ %{}) do
    Session.changeset(session, attrs)
  end

  def join_session_changeset(session, player_attrs \\ %{}) do
    Player.create_changeset(session, %Player{}, player_attrs)
  end

  def join_session(%{id: id} = session, player_attrs) do
    # Find open seats
    seats =
      Ecto.Query.from(p in Player, where: p.session_id == ^id, select: [:seat])
      |> Repo.all()
      |> Enum.map(& &1.seat)

    available_seats = Enum.filter(1..6, &(!Enum.member?(seats, &1)))

    case available_seats do
      [] ->
        {:no_space, "This game session is full, please try joining later"}

      seats ->
        # Random seat
        :random.seed(:os.timestamp())
        [seat | _] = Enum.shuffle(seats)
        player = %Player{seat: seat, session_id: id}

        player_changeset = Player.create_changeset(session, player, player_attrs)

        registration_multi =
          Multi.new()
          |> Multi.insert(:player, player_changeset)
          |> Multi.run(:buy_in, fn _repo, %{player: player} ->
            BuyIn.initial_changeset(session, %BuyIn{player_id: player.id}, %{
              amount: player.current_stack
            })
            |> Repo.insert()
          end)

        case Repo.transaction(registration_multi) do
          {:ok, %{player: player}} ->
            {:ok, player}

          {:error, :player, player_changeset, _} ->
            {:error, player_changeset}

          {:error, :buy_in, _, _} ->
            {:error, :buy_in, "Failed to buy in, please try again later"}
        end
    end
  end

  def player_quit(player_id, quit_at) do
    from(p in Player,
      where: p.id == ^player_id,
      update: [set: [sitting_out: true, seat: nil, quit_at: ^quit_at]]
    )
    |> Repo.update_all([])
  end

  @spec update_player_sitout(integer(), boolean()) :: any()
  def update_player_sitout(player_id, sitting_out) do
    from(p in Player,
      where: p.id == ^player_id,
      update: [set: [sitting_out: ^sitting_out]]
    )
    |> Repo.update_all([])
  end

  @spec update_player_stack(integer(), integer(), integer()) :: boolean()
  def update_player_stack(player_id, updated_stack, addon_amount) do
    multi =
      Multi.new()
      |> Multi.run(:buy_in, fn _, _ ->
        %BuyIn{player_id: player_id, amount: addon_amount}
        |> Repo.insert()
      end)
      |> Multi.run(:player, fn _, _ ->
        result =
          from(p in Player,
            where: p.id == ^player_id,
            update: [set: [current_stack: ^updated_stack]]
          )
          |> Repo.update_all([])

        case result do
          {0, _} -> {:error, :update_failure}
          {x, _} -> {:ok, x}
        end
      end)

    case Repo.transaction(multi) do
      {:ok, _} -> true
      _ -> false
    end
  end

  def subscribe(%{uuid: uuid}) do
    Phoenix.PubSub.subscribe(Dramaha.PubSub, "session:#{uuid}")
  end

  def broadcast_update(uuid, message \\ :state_update) do
    Phoenix.PubSub.broadcast(Dramaha.PubSub, "session:#{uuid}", message)
  end

  @spec cast_log_event(String.t(), String.t(), String.t()) :: :ok
  def cast_log_event(uuid, message, emitted_by) do
    pid = lookup_or_start_logger(uuid)
    GenServer.cast(pid, {:log, message, emitted_by})
  end

  @spec getn_log_events(String.t(), non_neg_integer()) :: list(Dramaha.ActionLogger.LogEntry.t())
  def getn_log_events(uuid, n) do
    pid = lookup_or_start_logger(uuid)
    GenServer.call(pid, {:get_top, n})
  end

  @spec subscribe_to_logs(String.t()) :: :ok
  def subscribe_to_logs(session_uuid) do
    Phoenix.PubSub.subscribe(Dramaha.PubSub, "session:#{session_uuid}:logs")
  end

  @spec broadcast_log_event(String.t(), LogEvent.t()) :: :ok
  def broadcast_log_event(session_uuid, log_event) do
    Phoenix.PubSub.broadcast(
      Dramaha.PubSub,
      "session:#{session_uuid}:logs",
      {:log_event, log_event}
    )
  end

  @spec subscribe_to_leaderboard(String.t()) :: :ok
  def subscribe_to_leaderboard(session_uuid) do
    Phoenix.PubSub.subscribe(Dramaha.PubSub, "session:#{session_uuid}:leaderboard")
  end

  @spec broadcast_leaderboard_entries(String.t(), list(Dramaha.Leaderboard.Entry.t())) :: :ok
  def broadcast_leaderboard_entries(session_uuid, entries) do
    Phoenix.PubSub.broadcast(
      Dramaha.PubSub,
      "session:#{session_uuid}:leaderboard",
      {:leaderboard_update, entries}
    )
  end

  @spec call_gameserver(Session.t(), Dramaha.Play.call()) :: Dramaha.Play.t()
  def call_gameserver(session, message) do
    GenServer.call(lookup_or_configure_gameserver(session), message)
  end

  @spec cast_gameserver(Session.t(), any()) :: :ok
  def cast_gameserver(session, message) do
    GenServer.cast(lookup_or_configure_gameserver(session), message)
  end

  @spec get_leaderboard(String.t()) :: Dramaha.Leaderboard.t()
  def get_leaderboard(uuid) do
    pid = lookup_or_configure_proc(uuid, Dramaha.Leaderboard)
    GenServer.call(pid, :query_state)
  end

  @spec update_leaderboard(String.t()) :: :ok
  def update_leaderboard(uuid) do
    pid = lookup_or_configure_proc(uuid, Dramaha.Leaderboard)
    GenServer.cast(pid, :update)
  end

  @spec lookup_or_configure_proc(String.t(), game_proc_type()) :: pid()
  defp lookup_or_configure_proc(uuid, proc_module) do
    suffix = proc_module.lookup_suffix
    registry_key = "#{uuid}#{suffix}"

    case Registry.lookup(Dramaha.PlayRegistry, registry_key) do
      [] ->
        session = get_session_by_uuid(uuid)
        start_and_configure_proc(session, proc_module, suffix)

      [{pid, _}] ->
        pid
    end
  end

  @spec start_and_configure_proc(Session.t(), game_proc_type(), String.t()) :: pid()
  defp start_and_configure_proc(session, proc_module, suffix) do
    case DynamicSupervisor.start_child(
           Dramaha.PlaySupervisor,
           {proc_module, name: via_registry(session.uuid, suffix)}
         ) do
      {:ok, pid} ->
        Enum.map(proc_module.configuration_messages(session), fn
          {:call, message} -> GenServer.call(pid, message)
          {:cast, message} -> GenServer.cast(pid, message)
        end)

        pid

      {:error, {:already_started, pid}} ->
        pid
    end
  end

  @spec lookup_or_configure_gameserver(Session.t()) :: pid()
  defp lookup_or_configure_gameserver(%{uuid: uuid} = session) do
    case Registry.lookup(Dramaha.PlayRegistry, uuid) do
      # If the gameserver is down (maybe we restarted the elixir server) we reconfigure the game session,
      # unique keys in the registry prevents a race condition.
      [] ->
        configure_gameserver(session)

      [{pid, _}] ->
        pid
    end
  end

  @spec configure_gameserver(Session.t()) :: pid()
  defp configure_gameserver(session) do
    config = %Dramaha.Game.Actions.Config{
      small_blind: session.small_blind,
      big_blind: session.big_blind
    }

    case DynamicSupervisor.start_child(
           Dramaha.PlaySupervisor,
           {Dramaha.Play, name: via_registry(session.uuid)}
         ) do
      {:ok, pid} ->
        GenServer.call(pid, {:configure_session, session.uuid, config, session.max_buy_in})
        pid

      {:error, {:already_started, pid}} ->
        pid
    end
  end

  @spec lookup_or_start_logger(String.t()) :: pid()
  defp lookup_or_start_logger(uuid) do
    registry_key = "#{uuid}-logger"

    case Registry.lookup(Dramaha.PlayRegistry, registry_key) do
      [] ->
        case DynamicSupervisor.start_child(
               Dramaha.PlaySupervisor,
               {Dramaha.ActionLogger, name: via_registry(uuid, "-logger")}
             ) do
          {:ok, pid} ->
            GenServer.call(pid, {:configure, uuid})
            pid

          {:error, {:already_started, pid}} ->
            pid
        end

      [{pid, _}] ->
        pid
    end
  end

  @spec via_registry(String.t(), String.t()) ::
          {:via, Registry, {Dramaha.PlayRegistry, String.t()}}
  defp via_registry(uuid, suffix \\ "") do
    {:via, Registry, {Dramaha.PlayRegistry, "#{uuid}#{suffix}"}}
  end
end
