defmodule Schism.CookiePool do
  use GenServer

  @moduledoc false

  @cookie_atoms (for index <- 1..256 do
                   String.to_atom("schism_partition_cookie_#{index}")
                 end)

  def acquire(id, nodes, manager_cookie) do
    ensure_started()
    GenServer.call(__MODULE__, {:acquire, id, nodes, manager_cookie})
  end

  def release(nodes) do
    ensure_started()
    GenServer.call(__MODULE__, {:release, nodes})
  end

  def init(:ok), do: {:ok, %{by_id: %{}, leases: %{}}}

  def handle_call({:acquire, id, nodes, manager_cookie}, _from, state) do
    case Map.fetch(state.by_id, id) do
      {:ok, cookie} ->
        state = remove_nodes(state, nodes, cookie)
        {:reply, {:ok, cookie}, add_nodes(state, cookie, nodes)}

      :error ->
        candidate_state = remove_nodes(state, nodes)

        case Enum.find(
               @cookie_atoms,
               &(&1 != manager_cookie and not Map.has_key?(candidate_state.leases, &1))
             ) do
          nil ->
            {:reply, :error, state}

          cookie ->
            lease = %{id: id, nodes: MapSet.new(nodes)}
            candidate_state = put_in(candidate_state, [:leases, cookie], lease)
            candidate_state = put_in(candidate_state, [:by_id, id], cookie)
            {:reply, {:ok, cookie}, candidate_state}
        end
    end
  end

  def handle_call({:release, nodes}, _from, state) do
    {:reply, :ok, remove_nodes(state, nodes)}
  end

  defp add_nodes(state, cookie, nodes) do
    update_in(
      state,
      [:leases, cookie, :nodes],
      &Enum.reduce(nodes, &1, fn n, acc -> MapSet.put(acc, n) end)
    )
  end

  defp remove_nodes(state, nodes, except_cookie \\ nil) do
    healed_nodes = MapSet.new(nodes)

    Enum.reduce(state.leases, state, fn {cookie, lease}, acc ->
      remaining_nodes =
        if cookie == except_cookie do
          lease.nodes
        else
          MapSet.difference(lease.nodes, healed_nodes)
        end

      if MapSet.size(remaining_nodes) == 0 do
        acc
        |> update_in([:leases], &Map.delete(&1, cookie))
        |> update_in([:by_id], &Map.delete(&1, lease.id))
      else
        put_in(acc, [:leases, cookie, :nodes], remaining_nodes)
      end
    end)
  end

  defp ensure_started do
    case GenServer.start(__MODULE__, :ok, name: __MODULE__) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end
end
