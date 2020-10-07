defmodule Dramaha.Game.Pot do
  alias Dramaha.Game.Player, as: Player

  # A pot is a 2-tuple of integers, the first represents the minimum amount of
  # chips a player had to commit to be eligible for winning the pot (assuming they made it to showdown)
  # and the second represents the actual value of the pot.
  @type pot_entry() :: {integer, integer}

  @spec __struct__ :: Dramaha.Game.Pot.t()
  @doc """
  full_pot is the total number of chips in the entirety of the pot including side pots,
  but not including chips that have been committed during the current betting street.

  pots is an array of ongoing pots in a hand in order that they are processed at showdown.
  The last pot is always the main pot.
  """
  defstruct full_pot: 0, committed: 0, pots: [{0, 0}]

  @type t() :: %__MODULE__{
          full_pot: integer(),
          committed: integer(),
          pots: list(pot_entry())
        }

  @doc """
  Gathers all the bets placed in a betting round and updates the pots and
  side pot totals
  """
  @spec gather_bets(t(), list(Player.t())) :: {t(), list(Player.t())}
  def gather_bets(pot, players) do
    %{full_pot: full_pot, committed: committed, pots: pots} = pot
    [current_pot_entry | other_pots] = pots

    updated_pot = %{pot | full_pot: full_pot + committed, committed: 0}

    pot_and_sidepots = update_pot_entry(current_pot_entry, players)

    # Due to the nature of the recursive algorithm's base case, we may end up with side pots of size 0.
    # This is by design, we simply need to just prune out the first pot if it's of size 0
    # It's impossible that this gets rid of the main pot because there's always some chips in the main pot.
    pot_entries =
      case pot_and_sidepots do
        [{_, 0} | other_sidepots] -> other_sidepots ++ other_pots
        pot_and_sidepots -> pot_and_sidepots ++ other_pots
      end

    {
      %{updated_pot | pots: pot_entries},
      Enum.map(players, &%{&1 | bet: 0})
    }
  end

  @doc """
  Pops out the next pot that needs to go to showdown and returns a list of indexes of
  players eligible to compete for this pot at showdown.
  """
  @spec pop_showdown(t(), list(Player.t())) :: {t(), integer(), list(integer())}
  def pop_showdown(pot, players) do
    %{pots: [next_pot | rest]} = pot
    {commit_requirement, pot_size} = next_pot

    players_with_index = Enum.with_index(players)

    eligible_indices =
      Enum.filter(players_with_index, fn {player, _} ->
        !Player.folded?(player) && player.committed >= commit_requirement
      end)
      |> Enum.map(fn {_, i} -> i end)

    {
      # remove the next_pot and subtract its size from the full pot
      %{pot | full_pot: pot.full_pot - pot_size, pots: [rest]},
      # Size of the side pot that's being competed for
      pot_size,
      eligible_indices
    }
  end

  @spec award_next_pot(t(), Player.t()) :: {t(), Player.t()}
  def award_next_pot(pot, %{stack: stack} = winner) do
    %{pots: [won_pot | next_pots]} = pot
    {_, pot_size} = won_pot

    {
      %{pot | pots: next_pots},
      %{winner | stack: stack + pot_size}
    }
  end

  @doc """
  Returns the list of players eligible to compete for the latest sidepot (or main pot)
  without creating any new pot structure.
  """
  @spec peek_eligible(t(), list(Player.t())) :: list({Player.t(), integer()})
  def peek_eligible(pot, players) do
    %{pots: [next_pot | _]} = pot
    {commit_requirement, _} = next_pot

    Enum.with_index(players)
    |> Enum.filter(fn {player, _} ->
      !Player.folded?(player) && player.committed >= commit_requirement
    end)
  end

  @spec update_pot_entry(pot_entry(), list(Player.t())) :: list(pot_entry())
  defp update_pot_entry({required_commit, pot_size}, players) do
    # Find the smallest bet made by any non-folded player
    # (essentially what is the smallest all in)
    min_committed_bet =
      Enum.filter(players, &(&1.bet > 0 && !Player.folded?(&1)))
      |> Enum.map(& &1.bet)
      |> Enum.min(fn -> 0 end)

    # We still need to keep track of folded players in our calculations because
    # they may still contribute to the gathering of the pot.
    cond do
      min_committed_bet == 0 ->
        [{required_commit, pot_size}]

      true ->
        {updated_players, total_chips} = match_smallest_bet(players, min_committed_bet)

        commit_for_next_sidepot = required_commit + min_committed_bet
        updated_pot_entry = {commit_for_next_sidepot, pot_size + total_chips}

        side_pots = update_pot_entry({commit_for_next_sidepot, 0}, updated_players)
        side_pots ++ [updated_pot_entry]
    end
  end

  @spec match_smallest_bet(list(Player.t()), integer()) :: {list(Player.t()), integer()}
  # This function essentially plays the same role as a dealer filling up the main pot, he takes
  # the bets that don't cover the shortest all in stack and gathers them, leaving the players with
  # the chips that will spill over into a side pot.
  defp match_smallest_bet(players, smallest_bet) do
    Enum.reduce(players, {[], 0}, fn player, {updated_players, total_chips} ->
      %{bet: bet} = player

      {
        # Subtract the smallest bet (or whatever was under it) from the total bet of the player
        updated_players ++ [%{player | bet: max(bet - smallest_bet, 0)}],
        # Add the smallest bet (or whatever was under it) to the total number of chips
        total_chips + min(bet, smallest_bet)
      }
    end)
  end
end
