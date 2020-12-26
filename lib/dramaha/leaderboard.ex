defmodule Dramaha.Leaderboard do
  @moduledoc """
  Genserver which logs messages in a game session and broadcasts new messages over pub sub
  """
  use GenServer, restart: :transient

  import Ecto.Query, warn: false

  alias Dramaha.Sessions
  alias Dramaha.Sessions.{BuyIn, Session, Player}
  alias Dramaha.Repo
  alias Dramaha.Leaderboard
  alias Dramaha.Leaderboard.Entry

  defstruct entries: [], session: nil

  @type t() :: %__MODULE__{
          session: Session.t(),
          entries: list(Entry.t())
        }

  @type cast() :: {:configure, String.t()} | :update

  def lookup_suffix do
    "-leaderboard"
  end

  def configuration_messages(session) do
    [{:cast, {:configure, session.uuid}}, {:cast, :update}]
  end

  def start_link(options) do
    GenServer.start_link(__MODULE__, %Dramaha.Leaderboard{}, options)
  end

  @impl true
  @spec init(t()) :: {:ok, t()}
  def init(state) do
    {:ok, state}
  end

  @impl true
  @spec handle_cast(cast(), t()) :: {:noreply, t()}
  def handle_cast({:configure, session_uuid}, state) do
    session = Sessions.get_session_by_uuid(session_uuid)

    {:noreply, %Leaderboard{state | session: session}}
  end

  def handle_cast(:update, %{session: nil} = state), do: {:noreply, state}

  def handle_cast(:update, state) do
    # Compute leaderboard entries
    leaderboard_tuples =
      from(
        b in BuyIn,
        join: p in Player,
        on: p.id == b.player_id,
        where: p.session_id == ^state.session.id,
        group_by: [p.id, p.current_stack, p.display_name],
        select: [p.id, p.current_stack, p.display_name, sum(b.amount)]
      )
      |> Repo.all()

    %{players: players} = Sessions.call_gameserver(state.session, :query_state)

    entries =
      Enum.map(leaderboard_tuples, fn [player_id, current_stack, display_name, total_buyins] ->
        case Enum.find(players, &(&1.player_id == player_id)) do
          %{stack: stack} ->
            # Use the stack from the game server state instead of the DB stack cause it's
            # usually more up to date
            %Entry{player_name: display_name, chips_won: stack - total_buyins}

          nil ->
            # Use the stack in the database. The player is not currently in the session.
            %Entry{
              player_name: display_name,
              chips_won: current_stack - total_buyins
            }
        end
      end)

    entries = Enum.sort_by(entries, & &1.chips_won, &>=/2)

    Sessions.broadcast_leaderboard_entries(state.session.uuid, entries)

    {:noreply,
     %{
       state
       | entries: entries
     }}
  end

  @impl true
  def handle_call(:query_state, _from, state) do
    {:reply, state, state}
  end
end
