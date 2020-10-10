defmodule Dramaha.Sessions.Session do
  use Ecto.Schema
  import Ecto.Changeset

  alias Dramaha.Sessions.Player

  schema "sessions" do
    field(:uuid, :string)
    field(:small_blind, :integer)
    field(:big_blind, :integer)
    field(:min_buy_in, :integer)
    field(:max_buy_in, :integer)

    has_many :players, Player

    timestamps()
  end

  def changeset(session, params \\ %{}) do
    session
    |> cast(params, [:small_blind, :big_blind, :min_buy_in, :max_buy_in])
    |> validate_required([:small_blind, :big_blind, :min_buy_in, :max_buy_in])
    |> validate_number(:small_blind, greater_than: 0)
    |> validate_number(:big_blind, greater_than: 0)
    |> validate_number(:min_buy_in, greater_than: 0)
    |> validate_number(:max_buy_in, greater_than: 0)
  end
end
