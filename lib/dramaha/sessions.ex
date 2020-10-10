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
    %Session{uuid: UUID.uuid4()}
    |> Session.changeset(attrs)
    |> Repo.insert()
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

  def subscribe(%{id: id}) do
    Phoenix.PubSub.subscribe(Dramaha.PubSub, "session:#{id}")
  end
end
