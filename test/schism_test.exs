defmodule SchismTest do
  use ExUnit.Case
  doctest Schism

  @moduletag :capture_log

  setup do
    {:ok, cluster} =
      LocalCluster.start_link(5,
        prefix: "partition-nodes",
        applications: []
      )

    {:ok, nodes} = LocalCluster.nodes(cluster)

    on_exit(fn ->
      if Process.alive?(cluster) do
        LocalCluster.stop(cluster)
      end
    end)

    {:ok, nodes: nodes}
  end

  test "partitions nodes", %{nodes: nodes} do
    [n1, n2, n3, n4, n5] = nodes

    partitions = [[n1, n2], [n3], [n4, n5]]

    for partition <- partitions do
      Schism.partition(partition)
    end

    for partition <- partitions, node <- partition do
      for n <- partition do
        assert :pong = :rpc.call(node, Node, :ping, [n])
      end

      for unreachable <- nodes -- partition do
        assert :pang == :rpc.call(node, Node, :ping, [unreachable])
      end
    end

    for partition <- partitions do
      Schism.heal(partition)
    end

    for node <- nodes do
      for other_node <- nodes, node != other_node do
        assert :pong = :rpc.call(node, Node, :ping, [other_node])
      end
    end
  end

  test "returns the nodes and reuses an explicit partition ID", %{nodes: nodes} do
    partition = Enum.take(nodes, 2)
    cookie = "explicit-partition-cookie"

    assert Schism.partition(partition, cookie) == partition

    [first | rest] = partition
    partition_cookie = :rpc.call(first, :erlang, :get_cookie, [])
    assert is_atom(partition_cookie)
    refute partition_cookie == :erlang.get_cookie()

    for node <- partition do
      assert partition_cookie == :rpc.call(node, :erlang, :get_cookie, [])
    end

    assert Schism.partition(rest, cookie) == rest
    assert partition_cookie == :rpc.call(hd(rest), :erlang, :get_cookie, [])
    assert Schism.heal(partition) == partition
  end

  test "reuses cookie atoms across repeated partitions", %{nodes: [first | _]} do
    Schism.partition([first], "cookie-pool-warm-up")
    Schism.heal([first])
    atom_count = :erlang.system_info(:atom_count)

    for index <- 1..100 do
      Schism.partition([first], "bounded-cookie-test-#{index}")
      Schism.heal([first])
    end

    assert :erlang.system_info(:atom_count) == atom_count
  end

  test "heals a partition and restores the manager cookie", %{nodes: nodes} do
    [first, second | _] = nodes
    manager_cookie = :erlang.get_cookie()

    Schism.partition([first, second], "temporary-partition-cookie")
    assert :pong == :rpc.call(first, Node, :ping, [second])

    assert Schism.heal([first, second]) == [first, second]
    assert manager_cookie == :rpc.call(first, :erlang, :get_cookie, [])
    assert manager_cookie == :rpc.call(second, :erlang, :get_cookie, [])
    assert :pong == :rpc.call(first, Node, :ping, [second])
  end

  test "handles empty and single-node partitions", %{nodes: [first, second | _]} do
    assert Schism.partition([]) == []
    assert Schism.partition([first]) == [first]
    assert :pang == :rpc.call(first, Node, :ping, [second])
    assert :pang == :rpc.call(second, Node, :ping, [first])

    assert Schism.heal([first, second]) == [first, second]
    assert :pong == :rpc.call(first, Node, :ping, [second])
  end
end
