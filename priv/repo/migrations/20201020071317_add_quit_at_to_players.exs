defmodule Dramaha.Repo.Migrations.AddQuitAtToPlayers do
  use Ecto.Migration

  def change do
    alter table(:players) do
      add :quit_at, :timestamp
      modify :seat, :integer, null: true, from: :integer
    end

    drop unique_index(:players, [:session_id, :seat])
    create unique_index(:players, [:session_id, :seat, :quit_at])
  end
end
