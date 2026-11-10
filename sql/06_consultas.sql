-- Valores por defecto para ejecutar los casos de uso con psql.
\set ON_ERROR_STOP on
\set instante now
\set dia today
\set cocinero_id 9
\set mesero_id 4
\set pedido_id 1
\set cliente_id 14
\set minutos_aviso 30
\set fecha_desde 2026-08-01
\set fecha_hasta 2028-01-01

-- PDF §3.1: muestra cada mesa y sus sillas, junto con la capacidad total del restaurante.
SELECT m.id AS mesa_id,
       m.sillas,
       SUM(m.sillas) OVER () AS sillas_totales
  FROM mesas m
 ORDER BY m.id;

-- PDF §3.2: muestra mesas sin cruces durante las dos horas alrededor del instante y el máximo de cupo ocupado en las dos horas siguientes.
WITH momento AS (
    SELECT :'instante'::TIMESTAMP AS inicio
), capacidad AS (
    SELECT COALESCE(SUM(m.sillas), 0) AS sillas_totales
      FROM mesas m
), instantes AS (
    SELECT inicio AS instante
      FROM momento
    UNION
    SELECT h.inicio
      FROM horarios h
      JOIN reservaciones r ON r.id = h.reservacion_id
      CROSS JOIN momento x
     WHERE r.estado IN (0, 1)
       AND h.inicio >= x.inicio
       AND h.inicio < x.inicio + INTERVAL '2 hours'
), ocupaciones AS (
    SELECT x.instante,
           COALESCE((
               SELECT SUM(r.cantidad)
                 FROM reservaciones r
                WHERE r.estado IN (0, 1)
                  AND EXISTS (
                      SELECT 1
                        FROM horarios h
                       WHERE h.reservacion_id = r.id
                         AND h.inicio <= x.instante
                         AND h.inicio > x.instante - INTERVAL '2 hours'
                  )
           ), 0) AS sillas_ocupadas
      FROM instantes x
), ocupacion_maxima AS (
    SELECT COALESCE(MAX(sillas_ocupadas), 0) AS sillas_ocupadas
      FROM ocupaciones
), mesas_libres AS (
    SELECT m.id, m.sillas
      FROM mesas m
      CROSS JOIN momento x
     WHERE NOT EXISTS (
               SELECT 1
                 FROM horarios h
                 JOIN reservaciones r ON r.id = h.reservacion_id
                WHERE h.mesa_id = m.id
                  AND r.estado IN (0, 1)
                  AND h.inicio > x.inicio - INTERVAL '2 hours'
                  AND h.inicio < x.inicio + INTERVAL '2 hours'
           )
)
SELECT m.id AS mesa_id,
       m.sillas,
       c.sillas_totales,
       o.sillas_ocupadas,
       c.sillas_totales - o.sillas_ocupadas AS sillas_libres
  FROM capacidad c
  CROSS JOIN ocupacion_maxima o
  LEFT JOIN mesas_libres m ON TRUE
 ORDER BY m.id;

-- PDF §3.2: lista las reservaciones que tienen un horario dentro del día elegido, con cliente, cantidad, estado y mesas.
SELECT r.id AS reservacion_id,
       u.nombre AS cliente,
       r.cantidad,
       r.estado,
       string_agg(h.mesa_id::TEXT, ', ' ORDER BY h.mesa_id) AS mesas,
       MIN(h.inicio) AS inicio
  FROM reservaciones r
  JOIN usuarios u ON u.id = r.cliente_id
  JOIN horarios h ON h.reservacion_id = r.id
 WHERE h.inicio >= :'dia'::DATE::TIMESTAMP
   AND h.inicio < (:'dia'::DATE + 1)::TIMESTAMP
 GROUP BY r.id, u.nombre, r.cantidad, r.estado
 ORDER BY inicio, r.id;

-- PDF §3.2: lista los clientes para elegir a quién se registra una reservación.
SELECT u.id,
       u.nombre
  FROM usuarios u
  JOIN actuaciones a ON a.usuario_id = u.id
  JOIN roles r ON r.id = a.rol_id
 WHERE r.nombre = 'cliente'
 ORDER BY u.nombre, u.id;

-- Consulta de la plantilla, opción Desplegar Menu: carta de platos agrupados por categoría.
SELECT platos.id,
       platos.nombre,
       tipos.nombre AS tipo,
       descripcion,
       precio
  FROM platos
  LEFT JOIN tipos ON platos.tipo_id = tipos.id
 ORDER BY tipos.id, platos.nombre;

-- PDF §3.3: presenta el menú ordenado por categoría, con descripción, tiempo en minutos y precio.
SELECT p.id,
       p.nombre,
       p.descripcion,
       p.tipo_id,
       t.nombre AS categoria,
       (EXTRACT(EPOCH FROM p.tiempo) / 60)::INT AS minutos,
       p.precio
  FROM platos p
  JOIN tipos t ON t.id = p.tipo_id
 ORDER BY t.id, p.nombre;

-- PDF §4.2: lista los empleados que gestiona el administrador (maitres, meseros y cocineros) con sus roles.
SELECT u.id,
       u.nombre,
       string_agg(r.nombre, ', ' ORDER BY r.nombre) AS roles
  FROM usuarios u
  JOIN actuaciones a ON a.usuario_id = u.id
  JOIN roles r ON r.id = a.rol_id
 WHERE r.nombre IN ('maitre', 'mesero', 'cocinero')
 GROUP BY u.id, u.nombre
 ORDER BY u.nombre;

-- PDF §2: muestra las especialidades del cocinero elegido para facilitar la asignación de platos.
SELECT u.id AS cocinero_id,
       u.nombre AS cocinero,
       p.id AS plato_id,
       p.nombre AS plato,
       p.tiempo
  FROM especialidades e
  JOIN usuarios u ON u.id = e.cocinero_id
  JOIN platos p ON p.id = e.plato_id
 WHERE e.cocinero_id = :cocinero_id
 ORDER BY p.nombre;

-- Consulta de la plantilla, opción Realizar Pedido: mesas con una reservación activa vigente ahora.
SELECT MES.id,
       MES.sillas,
       HOR.inicio,
       USR.nombre AS nombre_usr
  FROM mesas AS MES
  LEFT JOIN horarios AS HOR ON MES.id = HOR.mesa_id
  LEFT JOIN reservaciones AS RES ON RES.id = HOR.reservacion_id
  LEFT JOIN usuarios AS USR ON USR.id = RES.cliente_id
 WHERE HOR.inicio <= LOCALTIMESTAMP
   AND HOR.inicio > LOCALTIMESTAMP - INTERVAL '2 hours'
   AND RES.estado IN (0, 1)
 ORDER BY MES.id;

-- PDF §3.4: busca la reservación activa que ocupa la mesa ahora, para asociar el pedido a la mesa y al cliente.
\set mesa_id 11
SELECT r.cliente_id,
       u.nombre AS cliente
  FROM horarios h
  JOIN reservaciones r ON r.id = h.reservacion_id
  JOIN usuarios u ON u.id = r.cliente_id
 WHERE h.mesa_id = :mesa_id
   AND r.estado IN (0, 1)
   AND h.inicio <= LOCALTIMESTAMP
   AND h.inicio > LOCALTIMESTAMP - INTERVAL '2 hours'
 ORDER BY h.inicio DESC
 LIMIT 1;

-- PDF §3.4: muestra pedidos del mesero con mesa y estado derivados, limitando la lista a pendientes o pedidos de hoy.
SELECT d.pedido_id,
       c.nombre AS cliente,
       d.mesa_id,
       d.primer_solicitado,
       d.estado
  FROM pedidos_detalle d
  JOIN usuarios c ON c.id = d.cliente_id
 WHERE d.mesero_id = :mesero_id
   AND (d.estado <> 2 OR d.primer_solicitado >= CURRENT_DATE)
 ORDER BY d.primer_solicitado DESC, d.pedido_id;

-- PDF §3.4: detalla platos, cantidades, hora y estado de las órdenes del pedido seleccionado.
SELECT o.id AS orden_id,
       o.pedido_id,
       p.nombre AS plato,
       o.cantidad,
       o.solicitado,
       o.estado
  FROM ordenes o
  JOIN platos p ON p.id = o.plato_id
 WHERE o.pedido_id = :pedido_id
 ORDER BY o.solicitado, o.id;

-- PDF §2: presenta al cocinero sus órdenes pendientes de especialidades propias, empezando por los platos de mayor preparación.
SELECT o.id AS orden_id,
       p.nombre AS plato,
       (EXTRACT(EPOCH FROM p.tiempo) / 60)::INT AS minutos,
       o.cantidad,
       o.solicitado
  FROM especialidades e
  JOIN platos p ON p.id = e.plato_id
  JOIN ordenes o ON o.plato_id = p.id AND o.estado = 0
 WHERE e.cocinero_id = :cocinero_id
 ORDER BY p.tiempo DESC, o.solicitado, o.id;

-- PDF §3.5 y §4.1: muestra al mesero las órdenes preparadas de sus pedidos para que pueda avisar y entregarlas.
SELECT o.id AS orden_id,
       o.pedido_id,
       mesa_de_pedido(o.pedido_id) AS mesa_id,
       p.nombre AS plato,
       o.cantidad,
       o.solicitado
  FROM pedidos pe
  JOIN ordenes o ON o.pedido_id = pe.id
  JOIN platos p ON p.id = o.plato_id
 WHERE pe.mesero_id = :mesero_id
   AND o.estado = 1
 ORDER BY o.solicitado, o.id;

-- PDF §4.1: avisa únicamente las reservaciones aún reservadas cuyo primer horario empieza dentro del plazo configurado.
SELECT r.id AS reservacion_id,
       u.nombre AS cliente,
       r.cantidad,
       r.estado,
       string_agg(h.mesa_id::TEXT, ', ' ORDER BY h.mesa_id) AS mesas,
       MIN(h.inicio) AS inicio
  FROM reservaciones r
  JOIN usuarios u ON u.id = r.cliente_id
  JOIN horarios h ON h.reservacion_id = r.id
 WHERE r.estado = 0
   AND h.inicio >= LOCALTIMESTAMP
   AND h.inicio < LOCALTIMESTAMP + make_interval(mins => :minutos_aviso)
 GROUP BY r.id, u.nombre, r.cantidad, r.estado
 ORDER BY inicio, r.id;

-- PDF §3.6: cuenta una sola vez cada reservación no cancelada por su primer inicio dentro del rango; el periodo elegido es day, week o month.
\set periodo day
WITH primeros_inicios AS (
    SELECT h.reservacion_id,
           MIN(h.inicio) AS primer_inicio
      FROM horarios h
      JOIN reservaciones r ON r.id = h.reservacion_id
     WHERE r.estado <> 3
       AND h.inicio >= :'fecha_desde'::DATE::TIMESTAMP
       AND h.inicio < :'fecha_hasta'::DATE::TIMESTAMP
     GROUP BY h.reservacion_id
)
SELECT date_trunc(:'periodo', primer_inicio) AS inicio_periodo,
       COUNT(*) AS reservaciones
  FROM primeros_inicios
 GROUP BY date_trunc(:'periodo', primer_inicio)
 ORDER BY inicio_periodo;
\set periodo week
WITH primeros_inicios AS (
    SELECT h.reservacion_id,
           MIN(h.inicio) AS primer_inicio
      FROM horarios h
      JOIN reservaciones r ON r.id = h.reservacion_id
     WHERE r.estado <> 3
       AND h.inicio >= :'fecha_desde'::DATE::TIMESTAMP
       AND h.inicio < :'fecha_hasta'::DATE::TIMESTAMP
     GROUP BY h.reservacion_id
)
SELECT date_trunc(:'periodo', primer_inicio) AS inicio_periodo,
       COUNT(*) AS reservaciones
  FROM primeros_inicios
 GROUP BY date_trunc(:'periodo', primer_inicio)
 ORDER BY inicio_periodo;
\set periodo month
WITH primeros_inicios AS (
    SELECT h.reservacion_id,
           MIN(h.inicio) AS primer_inicio
      FROM horarios h
      JOIN reservaciones r ON r.id = h.reservacion_id
     WHERE r.estado <> 3
       AND h.inicio >= :'fecha_desde'::DATE::TIMESTAMP
       AND h.inicio < :'fecha_hasta'::DATE::TIMESTAMP
     GROUP BY h.reservacion_id
)
SELECT date_trunc(:'periodo', primer_inicio) AS inicio_periodo,
       COUNT(*) AS reservaciones
  FROM primeros_inicios
 GROUP BY date_trunc(:'periodo', primer_inicio)
 ORDER BY inicio_periodo;

-- PDF §3.6: suma cantidades por plato dentro del rango de solicitudes para identificar los más pedidos; no hay estado de orden cancelada.
SELECT p.id AS plato_id,
       p.nombre,
       SUM(o.cantidad) AS unidades_solicitadas
  FROM ordenes o
  JOIN platos p ON p.id = o.plato_id
 WHERE o.solicitado >= (:'fecha_desde'::DATE::TIMESTAMP AT TIME ZONE 'America/Bogota')
   AND o.solicitado < (:'fecha_hasta'::DATE::TIMESTAMP AT TIME ZONE 'America/Bogota')
 GROUP BY p.id, p.nombre
 ORDER BY unidades_solicitadas DESC, p.nombre;

-- PDF §3.6: suma cantidad por precio actual solo para órdenes entregadas, dentro del rango, agrupadas por el periodo elegido.
\set periodo day
SELECT date_trunc(:'periodo', o.solicitado AT TIME ZONE 'America/Bogota') AS inicio_periodo,
       SUM(o.cantidad * p.precio) AS ventas
  FROM ordenes o
  JOIN platos p ON p.id = o.plato_id
 WHERE o.estado = 2
   AND o.solicitado >= (:'fecha_desde'::DATE::TIMESTAMP AT TIME ZONE 'America/Bogota')
   AND o.solicitado < (:'fecha_hasta'::DATE::TIMESTAMP AT TIME ZONE 'America/Bogota')
 GROUP BY date_trunc(:'periodo', o.solicitado AT TIME ZONE 'America/Bogota')
 ORDER BY inicio_periodo;
\set periodo week
SELECT date_trunc(:'periodo', o.solicitado AT TIME ZONE 'America/Bogota') AS inicio_periodo,
       SUM(o.cantidad * p.precio) AS ventas
  FROM ordenes o
  JOIN platos p ON p.id = o.plato_id
 WHERE o.estado = 2
   AND o.solicitado >= (:'fecha_desde'::DATE::TIMESTAMP AT TIME ZONE 'America/Bogota')
   AND o.solicitado < (:'fecha_hasta'::DATE::TIMESTAMP AT TIME ZONE 'America/Bogota')
 GROUP BY date_trunc(:'periodo', o.solicitado AT TIME ZONE 'America/Bogota')
 ORDER BY inicio_periodo;
\set periodo month
SELECT date_trunc(:'periodo', o.solicitado AT TIME ZONE 'America/Bogota') AS inicio_periodo,
       SUM(o.cantidad * p.precio) AS ventas
  FROM ordenes o
  JOIN platos p ON p.id = o.plato_id
 WHERE o.estado = 2
   AND o.solicitado >= (:'fecha_desde'::DATE::TIMESTAMP AT TIME ZONE 'America/Bogota')
   AND o.solicitado < (:'fecha_hasta'::DATE::TIMESTAMP AT TIME ZONE 'America/Bogota')
 GROUP BY date_trunc(:'periodo', o.solicitado AT TIME ZONE 'America/Bogota')
 ORDER BY inicio_periodo;

-- PDF §4.3: muestra el historial completo de reservaciones del cliente, incluidas las que aún no tienen horario, con las más recientes primero.
SELECT r.id AS reservacion_id,
       r.cantidad,
       r.estado,
       string_agg(h.mesa_id::TEXT, ', ' ORDER BY h.mesa_id) AS mesas,
       MIN(h.inicio) AS primer_inicio
  FROM reservaciones r
  LEFT JOIN horarios h ON h.reservacion_id = r.id
 WHERE r.cliente_id = :cliente_id
 GROUP BY r.id, r.cantidad, r.estado
 ORDER BY primer_inicio DESC NULLS LAST, r.id DESC;

-- PDF §4.3: muestra todos los pedidos del cliente con mesa derivada y el estado del pedido y de cada orden.
SELECT d.pedido_id,
       d.mesa_id,
       d.primer_solicitado,
       d.estado AS estado_pedido,
       o.id AS orden_id,
       p.nombre AS plato,
       o.cantidad,
       o.estado AS estado_orden
  FROM pedidos_detalle d
  JOIN ordenes o ON o.pedido_id = d.pedido_id
  JOIN platos p ON p.id = o.plato_id
 WHERE d.cliente_id = :cliente_id
 ORDER BY d.primer_solicitado DESC, o.solicitado, o.id;

-- Operaciones de escritura de cada caso de uso. Corren en una transacción y se revierten al final,
-- de modo que este script nunca cambia los datos. Los triggers las validan igual que en la aplicación.
BEGIN;

-- PDF §3.1: agrega, modifica y elimina una mesa.
INSERT INTO mesas (sillas)
VALUES (4)
RETURNING id AS mesa_prueba \gset
UPDATE mesas
   SET sillas = 6
 WHERE id = :mesa_prueba;
DELETE FROM mesas
 WHERE id = :mesa_prueba;

-- PDF §3.3: agrega, modifica y elimina un plato.
INSERT INTO platos (nombre, descripcion, tipo_id, tiempo, precio)
VALUES ('Plato de demostración', 'Solo existe durante este script', 1, make_interval(mins => 20), 15000)
RETURNING id AS plato_prueba \gset
UPDATE platos
   SET precio = 16000
 WHERE id = :plato_prueba;
DELETE FROM platos
 WHERE id = :plato_prueba;

-- PDF §2 y §4.2: registra un cocinero y le asigna un plato que sabe preparar.
INSERT INTO usuarios (nombre, clave, fecha_clave)
VALUES ('Cocinero de demostración', convert_to('hash de demostración', 'UTF8'), now())
RETURNING id AS cocinero_prueba \gset
INSERT INTO actuaciones (usuario_id, rol_id)
SELECT :cocinero_prueba, id
  FROM roles
 WHERE nombre = 'cocinero';
SELECT id AS plato_pedido
  FROM platos
 ORDER BY id
 LIMIT 1 \gset
INSERT INTO especialidades (cocinero_id, plato_id)
VALUES (:cocinero_prueba, :plato_pedido);

-- PDF §3.2: registra una reservación con mesa y horario. Usa una mesa nueva para no chocar con otras.
INSERT INTO mesas (sillas)
VALUES (4)
RETURNING id AS mesa_reservada \gset
INSERT INTO reservaciones (cliente_id, cantidad)
VALUES (:cliente_id, 2)
RETURNING id AS reservacion_prueba \gset
INSERT INTO horarios (mesa_id, reservacion_id, inicio, duracion)
VALUES (:mesa_reservada, :reservacion_prueba, LOCALTIMESTAMP - INTERVAL '10 minutes', make_interval(mins => 90));
UPDATE reservaciones
   SET estado = 1
 WHERE id = :reservacion_prueba;

-- PDF §3.4: registra un pedido con dos platos para el cliente que ocupa la mesa.
INSERT INTO pedidos (cliente_id, mesero_id)
VALUES (:cliente_id, :mesero_id)
RETURNING id AS pedido_prueba \gset
INSERT INTO ordenes (plato_id, pedido_id, cantidad)
VALUES (:plato_pedido, :pedido_prueba, 2)
RETURNING id AS orden_prueba \gset
INSERT INTO ordenes (plato_id, pedido_id, cantidad)
SELECT id, :pedido_prueba, 1
  FROM platos
 ORDER BY id DESC
 LIMIT 1;

-- PDF §2: el cocinero registra la preparación y la orden pasa a preparado.
INSERT INTO preparaciones (cocinero_id, orden_id)
VALUES (:cocinero_prueba, :orden_prueba);
UPDATE ordenes
   SET estado = 1
 WHERE id = :orden_prueba;

-- PDF §3.5: el mesero entrega la orden preparada.
UPDATE ordenes
   SET estado = 2
 WHERE id = :orden_prueba;

-- PDF §3.2: modifica una reservación futura y luego la cancela.
INSERT INTO reservaciones (cliente_id, cantidad)
VALUES (:cliente_id, 2)
RETURNING id AS reservacion_futura \gset
INSERT INTO horarios (mesa_id, reservacion_id, inicio, duracion)
VALUES (:mesa_reservada, :reservacion_futura, LOCALTIMESTAMP + INTERVAL '30 days', make_interval(mins => 60));
UPDATE reservaciones
   SET cantidad = 3
 WHERE id = :reservacion_futura;
UPDATE reservaciones
   SET estado = 3
 WHERE id = :reservacion_futura;

-- Ejecuta ya las validaciones diferidas: si alguna regla fallara, el script se detendría aquí.
SET CONSTRAINTS ALL IMMEDIATE;
\echo 'Operaciones de escritura de todos los casos de uso: ejecutadas, validadas y revertidas.'

ROLLBACK;
