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

  test "returns the partition nodes and applies an explicit cookie", %{nodes: nodes} do
    partition = Enum.take(nodes, 2)
    cookie = "explicit-partition-cookie"

    assert Schism.partition(partition, cookie) == partition

    for node <- partition do
      assert String.to_atom(cookie) == :rpc.call(node, :erlang, :get_cookie, [])
    end
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
