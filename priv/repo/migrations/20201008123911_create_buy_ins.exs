defmodule Dramaha.Repo.Migrations.CreateBuyIns do
  use Ecto.Migration

  def change do
    create table(:buy_ins) do
      add(:player_id, references(:players, on_delete: :restrict), null: false, index: true)
      add(:amount, :integer, null: false)

      timestamps()
    end
  end
end
