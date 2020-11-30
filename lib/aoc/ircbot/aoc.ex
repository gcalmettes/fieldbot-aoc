defmodule Aoc.IrcBot.Aoc do
  use GenServer

  alias Aoc.Cache.Client, as: Cache
  alias Aoc.IrcBot.Formatter, as: Formatter
  alias ExIRC.Client, as: Irc

  @five_seconds 5000
  @bot_prefix "🤖 "
  @moduledoc """
  """
  def start! do
    start_link([])
  end

  def start_link(client) do
    GenServer.start_link(__MODULE__, client, name: :aocbot)
  end

  def init(client) do
    Irc.add_handler(client, self())
    Process.send_after(self(), :started, @five_seconds)
    {:ok, %{
      :client => client,
      :init => false,
      :channel => Application.fetch_env!(:aoc, Aoc.IrcBot)
        |> Keyword.get(:channel),
      :spam => Application.fetch_env!(:aoc, Aoc.IrcBot)
        |> Keyword.get(:spam)
    }}
  end

  def handle_cast(:today, state) do
    {:noreply, state}
  end

  def handle_cast(:heartbeat, state) do
    diff = Aoc.Rank.Announces.find_updates()

    cond do
      diff == [] ->
        :ok
      true ->
        updates = Formatter.updates(diff)
        Irc.msg(
          state[:client], :privmsg, state[:channel],
          updates
        )
    end

    scrape_time = DateTime.to_iso8601(DateTime.utc_now())
    Irc.msg(
        state[:client], :privmsg, state[:spam],
        @bot_prefix <> "Scraped leaderboards at "
        <> scrape_time
    )
    {:noreply, state}
  end

  def handle_info(:started, state) do
    {:noreply, %{state | :init => true}}
  end

  def handle_info(
      {:received, message, sender, channel},
      state = %{:init => true, :channel => channel}
  ) do
    from = sender.nick

    IO.puts "#{from} sent a message to #{channel}: #{message}"
    cond do
      String.starts_with?(message, "!crashtest") ->
        1 = 0
      String.starts_with?(message, "!formattest") ->
        Irc.msg(
            state[:client], :privmsg, state[:channel],
            @bot_prefix <> "Test <strong>*fsdfsfd*</strong>"
            <> "<pre>fsdf</pre><table><td>dsfsdf</td><td>dsfsdf</td></table>"
        )
      String.starts_with?(message, "!updatetest") ->
        GenServer.cast(Process.whereis(:aocbot), :heartbeat)
      String.starts_with?(message, "!2018") ->
        leaderboard = Cache.last("2018")
        Irc.msg(
            state[:client], :privmsg, state[:channel],
            @bot_prefix <> Formatter.leaderboard(leaderboard)
        )
      String.starts_with?(message, "!2019") ->
        leaderboard = Cache.last("2019")
        Irc.msg(
            state[:client], :privmsg, state[:channel],
            @bot_prefix <> Formatter.leaderboard(leaderboard)
        )
      String.starts_with?(message, "!2020") ->
        leaderboard = Cache.last("2020")
        Irc.msg(
            state[:client], :privmsg, state[:channel],
            @bot_prefix <> Formatter.leaderboard(leaderboard)
        )
      String.starts_with?(message, "!daily") ->
        diff = Aoc.Rank.Announces.daily_stats("2018")
        cond do
          diff == [] ->
            :ok
          true ->
            updates = Formatter.updates(diff)
            Irc.msg(
              state[:client], :privmsg, state[:channel],
              "Last <strong>24 hours</strong> : " <> updates
            )
        end
      String.starts_with?(message, "!help") ->
        Irc.msg(
          state[:client], :privmsg, state[:channel],
          @bot_prefix <> "I live to serve<BR>"
          <> @bot_prefix <> "<strong>!help</strong>: read this<BR>"
          <> @bot_prefix <> "<strong>![year]</strong>: show top5<BR>"
          <> @bot_prefix <> "<strong>!daily</strong>: 24 hours stats<BR>"
          <> @bot_prefix <> "<strong>!crashtest</strong>: crash the bot (on purpose)<BR>"
        )
      String.starts_with?(message, "!") ->
        Irc.msg(state[:client], :privmsg, channel,
          @bot_prefix <> " Come again ?"
        )
      true ->
        :ok
    end

    {:noreply, state}
  end

  def handle_info({:received, message, sender, channel}, state) do
    from = sender.nick
    IO.puts "#{from} sent a message to #{channel}: #{message}"
    {:noreply, state}
  end

  # Catch-all for messages you don't care about
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end


defmodule Aoc.IrcBot.Formatter do
  def ranked_member(rank, member) do
    ~s(##{rank+1}. ⭐ #{member["stars"]} ... )
    <> ~s(<strong>#{member["name"]}</strong>)
  end

  def updates(diff) do
    updates = diff
    |> Enum.map(&(
      "#{&1.name} grabs #{&1.new_stars} ⭐ (+#{&1.new_points} pts)"
    ))
    "Candies ! " <> Enum.join(updates, ", ")
  end

  def leaderboard(leaderboard) do
    message = "Leaderboard :<BR>"
    members = for {{_, s}, i} <- Aoc.Rank.Stats.by_rank(leaderboard)
        |> Enum.with_index()
        |> Enum.take(5), do: (
      ranked_member(i, s)
    )
    message <> Enum.join(members, "<BR>")
  end
end
