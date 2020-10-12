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

  def get_session_by_uuid(uuid), do: Repo.get_by(Session, uuid: uuid)

  def create_session(attrs) do
    session =
      %Session{uuid: UUID.uuid4()}
      |> Session.changeset(attrs)
      |> Repo.insert()

    configure_gameserver(session)

    session
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

  def subscribe(%{uuid: uuid}) do
    Phoenix.PubSub.subscribe(Dramaha.PubSub, "session:#{uuid}")
  end

  def broadcast_update(uuid) do
    Phoenix.PubSub.broadcast(Dramaha.PubSub, "session:#{uuid}", :state_update)
  end

  @spec call_gameserver(Dramaha.Sessions.Session.t(), Dramaha.Play.call()) :: Dramaha.Play.t()
  def call_gameserver(%{uuid: uuid} = session, message) do
    # The UUID identifies the play process for the session
    pid =
      case Registry.lookup(Dramaha.PlayRegistry, uuid) do
        # If the gameserver is down (maybe we restarted the elixir server) we reconfigure the game session,
        # unique keys in the registry prevents a race condition.
        [] ->
          configure_gameserver(session)

        [{pid, _}] ->
          pid
      end

    GenServer.call(pid, message)
  end

  @spec configure_gameserver(Dramaha.Sessions.Session.t()) :: pid()
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
        GenServer.call(pid, {:configure_session, session.uuid, config})
        pid

      {:error, {:already_started, pid}} ->
        pid
    end
  end

  @spec via_registry(String.t()) :: {:via, Registry, {Dramaha.PlayRegistry, String.t()}}
  defp via_registry(uuid) do
    {:via, Registry, {Dramaha.PlayRegistry, uuid}}
  end
end
