defmodule Dramaha.Repo.Migrations.CreateSessions do
  use Ecto.Migration

  def change do
    create table(:sessions) do
      add(:uuid, :string, null: false, unique: true)
      add(:small_blind, :integer, null: false)
      add(:big_blind, :integer, null: false)
      add(:min_buy_in, :integer, null: false)
      add(:max_buy_in, :integer, null: false)

      timestamps()
    end
  end
end
