# Schism

¿Querés probar qué hace tu aplicación cuando algunos nodos BEAM dejan de
verse entre sí? Schism te ayuda a simular esa situación desde un test, sin
tener que andar cortando conexiones de red a mano.

La idea es sencilla: elegís qué nodos van juntos, Schism los separa del resto
y después podés volver a unirlos. Está pensado para tests y desarrollo; no lo
uses para manejar particiones en producción.

## Instalación

Agregalo como dependencia de desarrollo o de test en `mix.exs`:

```elixir
def deps do
  [
    {:schism,
     git: "https://github.com/bossiernesto/schism.git",
     only: [:dev, :test]}
  ]
end
```

Después bajá las dependencias:

```bash
mix deps.get
```

## ¿Qué hace cuando particiona?

Schism usa las cookies de Erlang para que los nodos de una partición puedan
hablar entre ellos, pero no con los que quedaron afuera. A grandes rasgos:

1. Desconecta los nodos elegidos de los demás nodos que conocen.
2. Les cambia la cookie para separarlos del resto del cluster.
3. Vuelve a conectar entre sí los nodos que pasaste.

El nodo desde el que corrés el test conserva la posibilidad de administrar la
partición, así después podés llamar a `Schism.heal/1` y recuperar el cluster.

## Un ejemplo rápido

Si ya tenés algunos nodos levantados, podés dividirlos en grupos así:

```elixir
[n1, n2, n3, n4, n5] = nodes

# n1 y n3 quedan juntos; n4 queda solo; n2 y n5 forman otro grupo.
Schism.partition([n1, n3])
Schism.partition([n4])
Schism.partition([n2, n5])

# Acá poné las assertions de tu aplicación:
# por ejemplo, que detecte que perdió conexión con ciertos nodos.

# Cuando terminás, saná cada grupo.
Schism.heal([n1, n3])
Schism.heal([n4])
Schism.heal([n2, n5])
```

Los nodos que pasás en una llamada a `partition` se pueden ver entre sí. Los
que no están en esa lista quedan afuera de ese grupo.

Si necesitás elegir la cookie temporal, podés pasar un ID:

```elixir
Schism.partition([n1, n2], "mi-particion")
```

Si no pasás ese segundo argumento, Schism genera uno. Para volver al cluster
original, usá `heal` con los nodos que habías particionado:

```elixir
Schism.heal([n1, n2])
```

## Probalo en un test con LocalCluster

Si todavía no tenés nodos de prueba, [LocalCluster](https://hex.pm/packages/local_cluster)
te permite levantarlos localmente. Por ejemplo:

```elixir
test "la aplicación nota cuando dos nodos quedan aislados" do
  {:ok, cluster} =
    LocalCluster.start_link(3,
      prefix: "heartbeat-test",
      applications: []
    )

  {:ok, [first, second, third]} = LocalCluster.nodes(cluster)

  try do
    Schism.partition([first, second])

    assert :pong == :rpc.call(first, Node, :ping, [second])
    assert :pang == :rpc.call(first, Node, :ping, [third])

    # Agregá acá las assertions de tu propia aplicación.
  after
    Schism.heal([first, second])
    LocalCluster.stop(cluster)
  end
end
```

Ese `after` es útil: aunque falle una assertion, el test intenta sanar la
partición y detener el cluster antes de terminar.

## Importante si usás OTP 25 o posterior

Desde OTP 25, Erlang evita por defecto algunas particiones superpuestas.
Schism necesita permitirlas para poder simular estos escenarios, así que la
VM tiene que arrancar con esta opción:

```text
-kernel prevent_overlapping_partitions false
```

En este repo podés correr las pruebas con:

```bash
./bin/test
```

El script agrega la opción por vos. Si corrés tus propios tests con otro
comando, agregala a los argumentos de arranque de la VM y también a los nodos
remotos del test.

> Ojo: desactivar esta protección puede dejar inconsistente el estado de
> `global` o `mnesia` en una red real. Hacelo solamente en VMs aisladas para
> pruebas.

## ¿Qué no simula?

Schism te sirve para probar rápido cómo reacciona tu sistema cuando los nodos
se separan, pero no reemplaza una batería completa de tests distribuidos. No
simula, entre otras cosas:

- conexiones TCP que fallan de verdad;
- mensajes que llegan intercalados;
- condiciones de carrera;
- diferencias de reloj;
- corrupción de datos.

Usalo como una herramienta más: te resuelve el escenario de partición, y para
el resto conviene sumar tests específicos.
