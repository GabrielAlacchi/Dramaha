defmodule Dramaha.Repo.Migrations.CreatePlayers do
  use Ecto.Migration

  def change do
    create table(:players) do
      add(:session_id, references(:sessions, on_delete: :restrict), null: false)
      add(:display_name, :string, size: 20, null: false)
      add(:seat, :integer, null: false)
      add(:current_stack, :integer, null: :false)
      add(:sitting_out, :boolean, default: true, null: false)

      timestamps()
    end

    create unique_index(:players, [:session_id, :seat])
    create unique_index(:players, [:session_id, :display_name])
  end
end
