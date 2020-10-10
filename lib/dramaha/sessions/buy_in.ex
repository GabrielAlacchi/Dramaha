defmodule Dramaha.Sessions.BuyIn do
  use Ecto.Schema
  import Ecto.Changeset

  alias Dramaha.Sessions.Player

  schema "buy_ins" do
    belongs_to(:player, Player)

    field(:amount, :integer)

    timestamps()
  end

  def initial_changeset(session, buy_in, attrs \\ %{}) do
    buy_in
    |> cast(attrs, [:amount])
    |> validate_required([:amount])
    |> validate_number(:amount,
      greater_than_or_equal_to: session.min_buy_in,
      less_than_or_equal_to: session.max_buy_in
    )
  end

  def addon_changeset(session, player, buy_in, attrs \\ %{}) do
    buy_in
    |> cast(attrs, [:amount])
    |> validate_required([:amount])
    |> validate_change(:amount, fn :amount, amount ->
      new_stack = player.current_stack + amount

      cond do
        new_stack < session.min_buy_in ->
          [
            amount:
              "Your stack after the rebuy should exceed the min buy in of #{session.min_buy_in}"
          ]

        new_stack > session.max_buy_in ->
          [
            amount:
              "Your stack after the rebuy should not exceed the max buy in of #{
                session.max_buy_in
              }"
          ]

        true ->
          []
      end
    end)
  end
end
