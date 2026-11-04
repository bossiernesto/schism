# Schism

Schism sirve para simular particiones de red entre nodos BEAM (Erlang o
Elixir). Es útil cuando querés probar qué hace tu sistema cuando algunos
nodos dejan de verse entre sí, sin tener que cortar conexiones de red reales.

Está pensado para tests y desarrollo, no para usarse en producción.

## Cómo funciona

Schism usa una técnica sencilla basada en cookies de Erlang:

1. Toma los nodos que querés separar.
2. Desconecta esos nodos de los demás nodos conocidos.
3. Les asigna una cookie temporal diferente.
4. Vuelve a conectar entre sí los nodos de la partición.

Así, los nodos de una misma partición pueden comunicarse, pero no pueden
comunicarse con los nodos que quedaron afuera. El nodo que ejecuta el test se
mantiene como administrador de la partición para que después sea posible
repararla.

Cuando llamás a `Schism.heal/1`, Schism restaura la cookie original y vuelve a
conectar los nodos con el cluster.

## Instalación

Agregá Schism como dependencia de desarrollo o de test:

```elixir
def deps do
  [
    {:schism, git: "https://github.com/bossiernesto/schism.git", only: [:dev, :test]}
  ]
end
```

Después instalá las dependencias:

```bash
mix deps.get
```

## Uso básico

Supongamos que ya tenés cinco nodos corriendo:

```elixir
[n1, n2, n3, n4, n5] = nodes

# Los nodos de cada lista quedan juntos.
Schism.partition([n1, n3])
Schism.partition([n4])
Schism.partition([n2, n5])

# Acá probás el comportamiento de tu aplicación durante la partición.

# Al terminar, reparás cada partición.
Schism.heal([n1, n3])
Schism.heal([n4])
Schism.heal([n2, n5])
```

`Schism.partition/1` devuelve la lista de nodos que recibió:

```elixir
^partition = Schism.partition(partition)
```

También podés pasar una identificación explícita para la cookie temporal:

```elixir
Schism.partition([n1, n2], "mi-particion")
```

Normalmente no necesitás hacerlo; si omitís el segundo argumento, Schism
genera una cadena aleatoria.

## Probarlo con LocalCluster

Una forma práctica de crear nodos locales es usar
[LocalCluster](https://hex.pm/packages/local_cluster):

```elixir
{:ok, cluster} =
  LocalCluster.start_link(5,
    prefix: "test-node",
    applications: []
  )

{:ok, nodes} = LocalCluster.nodes(cluster)

[first, second | _] = nodes
Schism.partition([first, second])

# ... tus assertions ...

Schism.heal([first, second])
LocalCluster.stop(cluster)
```

## OTP 25 o posterior

Desde OTP 25, `global` evita por defecto las particiones superpuestas. Eso
está bueno para aplicaciones reales, pero Schism necesita justamente crear
esas particiones para probarlas.

Por eso tenés que iniciar la VM con esta opción:

```text
-kernel prevent_overlapping_partitions false
```

En este proyecto podés ejecutar los tests con el wrapper incluido:

```bash
./bin/test
```

El wrapper agrega automáticamente la opción necesaria. Si usás otro test
runner, agregá esa opción a los argumentos de la VM y asegurate de aplicarla
en todos los nodos del cluster.

> Esta opción puede dejar inconsistente el estado interno de `global` o
> `mnesia` en una red real. Usala solamente en VMs aisladas de test.

## Qué no prueba Schism

Schism es deliberadamente simple. No reemplaza una suite completa de tests
distribuidos y no simula:

- conexiones TCP fallidas;
- intercalado de mensajes;
- condiciones de carrera;
- diferencias de reloj;
- corrupción de datos;
- todos los problemas posibles de un sistema distribuido.

Usalo para probar rápido cómo reacciona tu aplicación cuando los nodos se
separan, y complementalo con tests más específicos para los demás casos.
