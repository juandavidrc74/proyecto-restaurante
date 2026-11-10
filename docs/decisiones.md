# Decisiones de diseño del Proyecto Restaurante

Fuentes: `2026.3-ProyectoRestaurante.pdf` (requisitos y diagrama entidad-relación de la sección 5) y la plantilla PHP. Decisiones aprobadas por el usuario el 2026-11-05.

## 1. Base de la aplicación

La base es la plantilla PHP (`index.php`, `esqueleto.html`, `etc/parametros.php`, `lib/libreria.php`, `lib/restaurante.php`, `lib/programa.js`, `css/estilo.css`). La frase del PDF sobre "la solución al parcial brindada por el docente" no aplica a este proyecto, según indicó el usuario.

## 2. Base de datos

- Motor: PostgreSQL 13.
- Base: `restaurante_proyecto`, propiedad de `estudiante`. La base anterior `restaurante` no se modifica.
- Tablespaces reutilizados: `ts_reservaciones_1`, `ts_reservaciones_2` y `ts_reservaciones_3`, en `/var/lib/pgsql/tablespaces/reservaciones_{1,2,3}`. El nombre es histórico.

## 3. Modelo (inmutable)

Doce tablas, sin columnas adicionales:

| Tabla | Columnas |
|---|---|
| tipos | id SERIAL PK, nombre TEXT |
| platos | id SERIAL PK, tipo_id INT FK tipos, nombre TEXT, descripcion TEXT, tiempo INTERVAL, precio NUMERIC |
| especialidades | id SERIAL PK, cocinero_id INT FK usuarios, plato_id INT FK platos |
| preparaciones | id SERIAL PK, cocinero_id INT FK usuarios, orden_id INT FK ordenes |
| ordenes | id SERIAL PK, plato_id INT FK platos, pedido_id INT FK pedidos, estado INT, cantidad INT, solicitado TIMESTAMP WITH TIME ZONE |
| pedidos | id SERIAL PK, cliente_id INT FK usuarios, mesero_id INT FK usuarios |
| usuarios | id SERIAL PK, nombre TEXT, clave BYTEA, fecha_clave TIMESTAMP |
| reservaciones | id SERIAL PK, cliente_id INT FK usuarios, cantidad INT, estado INT |
| horarios | id SERIAL, mesa_id INT FK mesas, reservacion_id INT FK reservaciones, inicio TIMESTAMP, duracion INTERVAL; PK (id, inicio), ver sección 6 |
| actuaciones | id SERIAL PK, rol_id INT FK roles, usuario_id INT FK usuarios |
| roles | id SERIAL PK, nombre TEXT |
| mesas | id SERIAL PK, sillas INT |

Valores de `estado`:
- `ordenes`: 0 solicitado, 1 preparado, 2 entregado. Equivalen a "en preparación", "listo" y "entregado" del PDF.
- `reservaciones`: 0 reservada, 1 ocupada, 2 liberada, 3 cancelada.

Datos fijos:
- `tipos`: entrada, plato fuerte, postre, bebida. El PDF exige cuatro categorías; la nota del diagrama solo lista tres.
- `roles`: administrador, maitre, mesero, cocinero, cliente.

## 4. Pedido y mesa

El diagrama no tiene `pedidos.mesa_id` y no se agrega. Un cliente siempre pasa antes por el maitre, que crea su reservación.

- Una orden solo se registra si el cliente del pedido tiene una reservación en estado reservada u ocupada cuyo horario cubre `ordenes.solicitado`.
- La mesa del pedido se deriva: de los horarios de las reservaciones no canceladas del cliente que cubren el primer `solicitado` del pedido, se toma el menor `mesa_id`.
- Si la reservación tiene varias mesas, el pedido queda asociado a una sola, la de menor número. El usuario aceptó esta limitación.

## 5. Duración y ocupación

- `horarios.duracion`: mayor que 0 y menor que 2 horas, como pide el diagrama. Es personalizable dentro de ese rango.
- La ocupación para cruces y cupo es siempre `[inicio, inicio + 2 horas)`, como pide el PDF. El instante final queda libre.

## 6. Partición

`horarios` se particiona por RANGE(`inicio`):

| Partición | Rango | Tablespace |
|---|---|---|
| horarios_1 | MINVALUE a 2026-10-01 | ts_reservaciones_1 |
| horarios_2 | 2026-10-01 a 2027-01-01 | ts_reservaciones_2 |
| horarios_3 | 2027-01-01 a MAXVALUE | ts_reservaciones_3 |

Motivo: solo tres columnas del modelo son fechas (`usuarios.fecha_clave`, `ordenes.solicitado`, `horarios.inicio`). PostgreSQL exige que la clave primaria de una tabla particionada incluya la columna de partición, y `usuarios` y `ordenes` reciben claves foráneas a su `id` que dejarían de ser posibles. `horarios` no recibe ninguna.

Consecuencia: la clave primaria física es `(id, inicio)` en lugar de `id`. Un trigger garantiza que `id` sea único en toda la tabla. La impone PostgreSQL. La otra posible diferencia con el diagrama es que `usuarios.clave` y `usuarios.fecha_clave` admiten nulos (sección 10), porque el diagrama no explica si su punto "•" significa obligatorio.

## 7. Cardinalidades

Se aplican como `NOT NULL` o reglas:
- `pedidos.cliente_id`, `pedidos.mesero_id` y `ordenes.plato_id` son obligatorios. El PDF exige asociar el pedido a un cliente y la orden a un ítem del menú.
- Toda reservación activa tiene al menos un horario al confirmar la transacción.
- Una orden no pasa a preparado sin al menos una preparación.

No se exige al crear: horarios de una mesa ni especialidades de un plato. Exigirlos impediría agregar mesas y platos, lo que el PDF pide expresamente.

## 8. Reglas de reservación

Una reservación está activa si su estado es reservada u ocupada. Solo las activas ocupan mesa y cupo.

- Sin cruces: dos reservaciones activas no ocupan la misma mesa en ventanas que se solapen.
- Cupo: en ningún instante la suma de `cantidad` de las reservaciones activas que ocupan alguna mesa supera la suma de `sillas` de todas las mesas. Cada reservación cuenta una sola vez aunque tenga varias mesas.
- Sillas suficientes: las mesas asignadas a una reservación activa suman al menos `cantidad`.
- Las validaciones se serializan con un bloqueo global de agenda y se protegen ante operaciones concurrentes.
- Cambiar `sillas` o `cantidad` vuelve a validar estas reglas.
- Estados: reservada pasa a ocupada o cancelada; ocupada pasa a liberada o cancelada; liberada y cancelada son finales.

## 9. Pedidos, preparación y entrega

- El cocinero marca preparado y debe tener la especialidad del plato. El mesero marca entregado.
- Estados de orden: 0 a 1 a 2, sin retrocesos.
- Estado del pedido, derivado de sus órdenes: entregado si todas están entregadas; listo si todas están preparadas o entregadas; en preparación en otro caso.

## 10. Acceso

Inicio de sesión mínimo: se elige el empleado de una lista y se escribe su `clave`, guardada como hash de `password_hash()` de PHP en el BYTEA. `nombre` no es único. Los clientes no inician sesión, por lo que `clave` y `fecha_clave` admiten nulos y solo son nulos juntos. Las opciones originales de la plantilla (Desplegar Menú y Realizar Pedido) se mantienen.

## 11. Notificaciones

Se calculan por consulta, sin tablas, y se muestran en la página del rol, actualizadas desde `lib/programa.js`. Por tanto, el aviso solo aparece con la página abierta.
- Mesero: órdenes de sus pedidos en estado preparado.
- Maitre: reservaciones en estado reservada que comienzan en los próximos 30 minutos, valor configurable en `etc/parametros.php`.

## 12. Reportes y eliminaciones

- Más solicitados: suma de `ordenes.cantidad` por plato.
- Ventas: `cantidad × platos.precio` de las órdenes entregadas, por fecha de `solicitado`. Se usa el precio actual porque el diagrama no guarda precios históricos, así que cambiar un precio altera las ventas pasadas.
- Reservaciones por día, semana o mes: según `horarios.inicio`.
- Un plato o una mesa con historial no se pueden eliminar, para conservarlo.
- Las especialidades de un plato o cocinero eliminado se eliminan con él.
- El maitre puede registrar clientes nuevos, porque el administrador solo registra empleados y sin esto un cliente nuevo no podría reservar.

## 13. Aclaraciones posteriores

Surgieron en la revisión independiente de la aplicación. Precisan lo anterior sin agregar tablas, columnas ni módulos. **El usuario las confirmó el 2026-11-08.**

### Estado de los pedidos: quién hace qué

El PDF dice en su sección 2 que el mesero actualiza el estado "en preparación, listo, entregado" y que el cocinero lo actualiza a "listo". El diagrama exige que una preparación tenga un cocinero con la especialidad del plato. Por eso:

- "En preparación" es el estado inicial de toda orden. Nadie lo marca.
- "Listo" lo marca el cocinero, que queda registrado en `preparaciones`.
- "Entregado" lo marca el mesero.
- El mesero ve los tres estados, pero solo actualiza el último.

### Protección de lo que ya tiene pedidos

La mesa de un pedido se deriva de los horarios de la reservación (sección 4). Para que esa asociación no se pierda, la base rechaza lo siguiente:

- Mientras un horario sea la mesa de un pedido: borrarlo, cambiar su inicio, su mesa o su reservación.
- Si la reservación tiene pedidos: cancelarla o cambiar su cliente. Sí se puede liberar. Esto precisa la sección 8.
- Si el pedido tiene órdenes: cambiar su cliente.
- Una orden solo se edita o se borra mientras esté solicitada y sin preparaciones, y nunca cambia su pedido ni su fecha.
- Una preparación no se altera si su orden ya está preparada o entregada.
- No se quita un rol que tenga historial.

Sí se puede agregar una mesa a una reservación con pedidos, cambiar su duración y quitar una mesa que no sea la del pedido. Si la mesa agregada tiene un número menor, pasa a ser la mesa del pedido, por la regla de la sección 4, y ya no se puede quitar.

### Interpretaciones del PDF

- **Agregar ítems a un pedido (3.4):** se agregan varios platos al crear el pedido. Si el cliente pide algo después, el mesero registra otro pedido para la misma mesa, con su propio estado.
- **Gestionar empleados (4.2):** incluye registrar, cambiar nombre y clave, y eliminar. El rol no se cambia: un empleado sin historial se elimina y se registra de nuevo, y a uno con historial la base no le permite perder su rol.
- **Reportes (3.6):** además de agrupar por día, semana o mes, permiten elegir un rango de fechas. Por omisión van desde el 1 de enero hasta hoy, de modo que las reservaciones futuras se ven ampliando la fecha final. El reporte de reservaciones excluye las canceladas.
- **Consultar por categoría (instrucciones del proyecto, pruebas de Menú):** el menú se consulta ordenado por categoría y muestra la categoría de cada plato. No hay filtro por categoría, porque el PDF no lo pide.
- **Mesas en Realizar Pedido (3.4):** solo se listan las mesas con una reservación vigente en este momento, la única condición con la que se puede registrar un pedido. Esto cambia el filtro de la consulta de la plantilla.

### Reglas adicionales

- `uq_platos_nombre`: dos platos no pueden tener el mismo nombre. No lo pide el PDF. Se conserva como restricción de integridad, para que los meseros no confundan los platos.
- `ck_platos_precio_valido`: además de no ser negativo, el precio no puede ser `NaN`, porque dañaría las ventas.
- El administrador no puede eliminar su propia cuenta, porque perdería el acceso. No administra a otros administradores: el PDF solo menciona maitres, meseros y cocineros.

### Limitaciones conocidas

- **Plato sin especialista.** Se puede pedir, porque el PDF exige poder agregar platos. Su orden espera hasta que el administrador asigne el plato a un cocinero. Los datos de prueba no tienen este caso.
- **Reservación vieja sin cerrar.** Sigue contando como activa. Puede impedir reducir las sillas de su mesa hasta que el maitre la cancele, y el mensaje de error indica cuál es.
- **Entregar desde el formulario de pedido.** El botón del aviso lleva a Pedidos y descarta las cantidades que se estuvieran escribiendo.
- **Recargar la página tras un envío** repite el envío, y el navegador avisa antes. En un pedido crearía uno duplicado.
- **Zona horaria.** La hora actual de la base depende de la zona del servidor, que en la máquina virtual es `America/Bogota`, la misma que usan PHP y los reportes.
