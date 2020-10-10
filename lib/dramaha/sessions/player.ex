defmodule Dramaha.Sessions.Player do
  use Ecto.Schema
  import Ecto.Changeset

  alias Dramaha.Sessions.Session

  schema "players" do
    belongs_to(:session, Session)
    field(:display_name, :string)
    field(:seat, :integer)
    field(:current_stack, :integer)
    field(:sitting_out, :boolean, default: true)

    timestamps()
  end

  def create_changeset(session, player, params \\ %{}) do
    player
    |> cast(params, [:display_name, :current_stack])
    |> validate_required([:display_name, :current_stack])
    |> validate_length(:display_name, min: 2, max: 20)
    |> validate_number(:current_stack,
      greater_than_or_equal_to: session.min_buy_in,
      less_than_or_equal_to: session.max_buy_in
    )
    |> unique_constraint([:session_id, :display_name])
  end
end
