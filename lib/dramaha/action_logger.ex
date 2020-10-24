defmodule Dramaha.ActionLogger do
  @moduledoc """
  Genserver which logs messages in a game session and broadcasts new messages over pub sub
  """
  use GenServer, restart: :transient

  alias Dramaha.Sessions
  alias Dramaha.ActionLogger.LogEntry

  # Log entries will be prepended to the list (more effecient as the list grows)
  defstruct log_entries: [], session_uuid: ""

  @type t() :: %__MODULE__{
          session_uuid: String.t(),
          log_entries: list(LogEntry.t())
        }

  @type call() :: {:configure, String.t()} | {:get_top, non_neg_integer()}
  @type cast() :: {:log, String.t(), String.t()}

  def start_link(options) do
    GenServer.start_link(__MODULE__, %Dramaha.ActionLogger{}, options)
  end

  @impl true
  @spec init(t()) :: {:ok, t()}
  def init(state) do
    {:ok, state}
  end

  @impl true
  @spec handle_call(call(), GenServer.from(), t()) :: {:reply, any(), t()}
  def handle_call({:configure, uuid}, _from, state) do
    state = %{state | session_uuid: uuid}
    {:reply, state, state}
  end

  def handle_call({:get_top, n}, _from, state) do
    {:reply, Enum.take(state.log_entries, n), state}
  end

  @impl true
  @spec handle_cast(cast(), t()) :: {:noreply, t()}
  def handle_cast({:log, message, emitted_by}, %{log_entries: entries} = state) do
    next_sequence =
      case entries do
        [] -> 0
        [%{sequence: s} | _] -> s + 1
      end

    new_entry = %LogEntry{
      message: message,
      emitted_by: emitted_by,
      sequence: next_sequence,
      timestamp: DateTime.utc_now()
    }

    Sessions.broadcast_log_event(state.session_uuid, new_entry)
    {:noreply, %{state | log_entries: [new_entry | entries]}}
  end
end
