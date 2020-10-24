defmodule Dramaha.ActionLogger.LogEntry do
  @enforce_keys [:sequence, :message, :emitted_by, :timestamp]
  defstruct [:sequence, :message, :emitted_by, :timestamp]

  @type t() :: %__MODULE__{
          sequence: non_neg_integer(),
          message: String.t(),
          emitted_by: String.t(),
          timestamp: DateTime.t()
        }
end
