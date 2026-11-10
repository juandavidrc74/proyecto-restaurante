-- Datos ficticios deterministas para desarrollo y demostración.
-- La carga siempre usa las restricciones y los triggers reales del esquema.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL TIME ZONE 'America/Bogota';

TRUNCATE TABLE
    preparaciones,
    especialidades,
    ordenes,
    pedidos,
    actuaciones,
    horarios,
    reservaciones,
    platos,
    mesas,
    usuarios,
    tipos,
    roles
RESTART IDENTITY CASCADE;

INSERT INTO roles (nombre) VALUES
    ('administrador'),
    ('maitre'),
    ('mesero'),
    ('cocinero'),
    ('cliente');

INSERT INTO tipos (nombre) VALUES
    ('entrada'),
    ('plato fuerte'),
    ('postre'),
    ('bebida');

-- El hash de demostración corresponde a la contraseña restaurante2026.
INSERT INTO usuarios (id, nombre, clave, fecha_clave)
SELECT e.id,
       e.nombre,
       convert_to('$2y$10$mLhxw6U.FPhPJVSp0p.Nl.zEcYqTXV.0PWoBwb6Vc9A1f4puHd0bO', 'UTF8'),
       now()
  FROM (VALUES
      (1, 'Aurelia Pardo'),
      (2, 'Marleny Cárdenas'),
      (3, 'Jhonatan Rincón'),
      (4, 'Brayan Quintero'),
      (5, 'Leidy Mosquera'),
      (6, 'Yeison Ocampo'),
      (7, 'Mónica Téllez'),
      (8, 'Wilmer Buitrago'),
      (9, 'Yulieth Arboleda'),
      (10, 'Fabio Chacón'),
      (11, 'Nidia Cifuentes'),
      (12, 'Harold Patiño'),
      (13, 'Sonia Guarín')
  ) AS e(id, nombre);

INSERT INTO usuarios (id, nombre, clave, fecha_clave) VALUES
    (14, 'Ángela Caicedo', NULL, NULL),
    (15, 'Maicol Beltrán', NULL, NULL),
    (16, 'Yadira Salcedo', NULL, NULL),
    (17, 'Jhon Fajardo', NULL, NULL),
    (18, 'Leider Pineda', NULL, NULL),
    (19, 'Milena Cerón', NULL, NULL),
    (20, 'Yerson Baquero', NULL, NULL),
    (21, 'Luz Marina Cuéllar', NULL, NULL),
    (22, 'Óscar Julián Porras', NULL, NULL),
    (23, 'Tatiana Bolaños', NULL, NULL),
    (24, 'Camilo Andrés Perea', NULL, NULL),
    (25, 'Valentina Noreña', NULL, NULL),
    (26, 'Santiago Londoño', NULL, NULL),
    (27, 'María Fernanda Solano', NULL, NULL),
    (28, 'Nicolás Ceballos', NULL, NULL),
    (29, 'Isabela Murillo', NULL, NULL),
    (30, 'Esteban Ordóñez', NULL, NULL),
    (31, 'Paola Andrea Hoyos', NULL, NULL),
    (32, 'Sebastián Cuervo', NULL, NULL),
    (33, 'Natalia Becerra', NULL, NULL),
    (34, 'Tomás Villamil', NULL, NULL),
    (35, 'Manuela Castaño', NULL, NULL),
    (36, 'Samuel Gaitán', NULL, NULL),
    (37, 'Juliana Lemos', NULL, NULL),
    (38, 'Emilio Santacruz', NULL, NULL),
    (39, 'Sara Valderrama', NULL, NULL),
    (40, 'Andrés Felipe Burbano', NULL, NULL),
    (41, 'Gabriela Peñaloza', NULL, NULL),
    (42, 'Mateo Figueroa', NULL, NULL),
    (43, 'Laura Marcela Cerquera', NULL, NULL),
    (44, 'David Estupiñán', NULL, NULL),
    (45, 'Salomé Villota', NULL, NULL),
    (46, 'Felipe Zambrano', NULL, NULL),
    (47, 'Candelaria Rojas', NULL, NULL),
    (48, 'Nicolás Erazo', NULL, NULL),
    (49, 'Mariana Burbano', NULL, NULL),
    (50, 'Emmanuel Pantoja', NULL, NULL),
    (51, 'Cecilia Narváez', NULL, NULL),
    (52, 'Jerónimo Chaves', NULL, NULL),
    (53, 'Antonella Rosero', NULL, NULL);
SELECT setval(pg_get_serial_sequence('usuarios', 'id'), 53, TRUE);

INSERT INTO actuaciones (rol_id, usuario_id)
SELECT r.id, u.id
  FROM (VALUES
      ('Aurelia Pardo', 'administrador'),
      ('Marleny Cárdenas', 'maitre'),
      ('Jhonatan Rincón', 'maitre'),
      ('Brayan Quintero', 'mesero'),
      ('Leidy Mosquera', 'mesero'),
      ('Yeison Ocampo', 'mesero'),
      ('Mónica Téllez', 'mesero'),
      ('Wilmer Buitrago', 'mesero'),
      ('Yulieth Arboleda', 'cocinero'),
      ('Fabio Chacón', 'cocinero'),
      ('Nidia Cifuentes', 'cocinero'),
      ('Harold Patiño', 'cocinero'),
      ('Sonia Guarín', 'cocinero')
  ) AS asignacion(nombre, rol)
  JOIN usuarios u ON u.nombre = asignacion.nombre
  JOIN roles r ON r.nombre = asignacion.rol;

INSERT INTO actuaciones (rol_id, usuario_id)
SELECT r.id, u.id
  FROM usuarios u
  JOIN roles r ON r.nombre = 'cliente'
 WHERE u.clave IS NULL;

INSERT INTO mesas (id, sillas) VALUES
    (1, 2), (2, 4), (3, 6), (4, 8), (5, 2),
    (6, 4), (7, 6), (8, 8), (9, 2), (10, 4),
    (11, 6), (12, 8), (13, 2), (14, 4), (15, 6);
SELECT setval(pg_get_serial_sequence('mesas', 'id'), 15, TRUE);

INSERT INTO platos (id, tipo_id, nombre, descripcion, tiempo, precio)
SELECT p.id, t.id, p.nombre, p.descripcion, p.tiempo, p.precio
  FROM (VALUES
      (1, 'entrada', 'Arepa de choclo con queso', 'Arepa dorada de maíz tierno con queso campesino.', INTERVAL '10 minutes', 8500),
      (2, 'entrada', 'Crema de ahuyama', 'Crema suave de ahuyama con cilantro y semillas tostadas.', INTERVAL '20 minutes', 12000),
      (3, 'entrada', 'Empanadas de pipián', 'Empanadas de masa de maíz con papa colorada y maní.', INTERVAL '30 minutes', 14000),
      (4, 'entrada', 'Patacón con hogao', 'Patacón crocante servido con hogao de tomate y cebolla.', INTERVAL '45 minutes', 11000),
      (5, 'entrada', 'Ceviche de champiñones', 'Champiñones marinados con limón, cebolla morada y cilantro.', INTERVAL '15 minutes', 18000),
      (6, 'entrada', 'Carimañolas de yuca', 'Carimañolas rellenas de queso y acompañadas de ají casero.', INTERVAL '25 minutes', 13000),
      (7, 'plato fuerte', 'Ajiaco santafereño', 'Sopa bogotana de pollo, papa criolla, mazorca y guascas.', INTERVAL '35 minutes', 32000),
      (8, 'plato fuerte', 'Bandeja paisa', 'Fríjoles, arroz, carne, chicharrón, huevo, arepa y aguacate.', INTERVAL '40 minutes', 38000),
      (9, 'plato fuerte', 'Sobrebarriga en salsa', 'Sobrebarriga cocida lentamente con salsa criolla y papa.', INTERVAL '50 minutes', 36000),
      (10, 'plato fuerte', 'Trucha al ajillo', 'Trucha a la plancha con ajo, limón, papa y ensalada fresca.', INTERVAL '30 minutes', 34000),
      (11, 'plato fuerte', 'Arroz atollado', 'Arroz del Valle con pollo, cerdo, papa amarilla y hogao.', INTERVAL '45 minutes', 30000),
      (12, 'plato fuerte', 'Lomo en salsa de panela', 'Lomo de res con reducción de panela y vegetales asados.', INTERVAL '25 minutes', 42000),
      (13, 'postre', 'Obleas con arequipe', 'Oblea crujiente rellena de arequipe y queso rallado.', INTERVAL '8 minutes', 9000),
      (14, 'postre', 'Cuajada con melao', 'Cuajada fresca acompañada de melao de panela.', INTERVAL '12 minutes', 10000),
      (15, 'postre', 'Arroz con leche', 'Arroz con leche cremosa, canela y ralladura de naranja.', INTERVAL '18 minutes', 11000),
      (16, 'postre', 'Brevas con arequipe', 'Brevas cocidas lentamente servidas con arequipe.', INTERVAL '16 minutes', 12000),
      (17, 'postre', 'Torta de almojábana', 'Torta tibia de queso y almojábana con centro suave.', INTERVAL '22 minutes', 14000),
      (18, 'postre', 'Merengón de guanábana', 'Merengue horneado con crema y pulpa de guanábana.', INTERVAL '28 minutes', 16000),
      (19, 'bebida', 'Limonada de panela', 'Limonada fresca endulzada con panela artesanal.', INTERVAL '5 minutes', 7000),
      (20, 'bebida', 'Aguapanela con limón', 'Aguapanela tradicional servida fría o caliente.', INTERVAL '6 minutes', 6000),
      (21, 'bebida', 'Jugo de lulo', 'Jugo natural de lulo preparado al momento.', INTERVAL '7 minutes', 8500),
      (22, 'bebida', 'Jugo de mora', 'Jugo natural de mora con agua o leche.', INTERVAL '9 minutes', 8500),
      (23, 'bebida', 'Chocolate santafereño', 'Chocolate de mesa batido y servido con canela.', INTERVAL '11 minutes', 8000),
      (24, 'bebida', 'Kumis de la casa', 'Kumis frío de preparación artesanal.', INTERVAL '4 minutes', 7500)
  ) AS p(id, categoria, nombre, descripcion, tiempo, precio)
  JOIN tipos t ON t.nombre = p.categoria
 ORDER BY p.id;
SELECT setval(pg_get_serial_sequence('platos', 'id'), 24, TRUE);

-- Cada plato tiene especialista; las asignaciones adicionales varían los reportes.
WITH cocineros AS (
    SELECT u.id,
           row_number() OVER (ORDER BY u.id) - 1 AS posicion
      FROM usuarios u
      JOIN actuaciones a ON a.usuario_id = u.id
      JOIN roles r ON r.id = a.rol_id
     WHERE r.nombre = 'cocinero'
), asignaciones AS (
    SELECT c.id AS cocinero_id, p.id AS plato_id
      FROM platos p
      JOIN cocineros c ON c.posicion = mod(p.id - 1, 5)
    UNION ALL
    SELECT c.id, p.id
      FROM platos p
      JOIN cocineros c ON c.posicion = mod(p.id + 1, 5)
     WHERE mod(p.id, 3) = 0
)
INSERT INTO especialidades (cocinero_id, plato_id)
SELECT cocinero_id, plato_id FROM asignaciones;

DO $$
DECLARE
    v_hoy DATE := CURRENT_DATE;
    v_dias_historicos INTEGER;
    v_dia INTEGER;
    v_fecha DATE;
    v_hora TIME;
    v_inicio TIMESTAMP;
    v_numero INTEGER := 0;
    v_turno INTEGER;
    v_reservacion_id INTEGER;
    v_cliente_id INTEGER;
    v_mesero_id INTEGER;
    v_pedido_id INTEGER;
    v_orden_id INTEGER;
    v_plato_id INTEGER;
    v_cocinero_id INTEGER;
    v_mesa_principal INTEGER;
    v_mesa_secundaria INTEGER;
    v_cantidad INTEGER;
    v_cantidad_ordenes INTEGER;
    v_numero_orden INTEGER;
    v_grupo BOOLEAN;
    v_pedido_historico BOOLEAN;
    v_ahora TIMESTAMP := date_trunc('minute', now()::TIMESTAMP);
    v_pedido_demo_1 INTEGER;
    v_pedido_demo_2 INTEGER;
    v_estado_orden INTEGER;
    v_fecha_futura DATE;
    v_hora_futura TIME;
BEGIN
    -- Cinco turnos diarios desde agosto hasta ayer; los turnos son contiguos.
    v_dias_historicos := v_hoy - DATE '2026-08-01';
    IF v_dias_historicos > 0 THEN
        FOR v_dia IN 0..(v_dias_historicos - 1) LOOP
            v_fecha := DATE '2026-08-01' + v_dia;
            FOR v_turno IN 0..4 LOOP
                v_numero := v_numero + 1;
                v_hora := TIME '12:00' + v_turno * INTERVAL '2 hours';
                v_inicio := v_fecha + v_hora;
                v_mesa_principal := v_turno + 1;
                v_mesa_secundaria := v_turno + 6;
                v_grupo := mod(v_numero, 13) = 0;
                v_pedido_historico := mod(v_numero, 10) <> 0
                                      AND mod(v_numero, 5) <> 0;

                SELECT u.id INTO v_cliente_id
                  FROM usuarios u
                  JOIN actuaciones a ON a.usuario_id = u.id
                  JOIN roles r ON r.id = a.rol_id
                 WHERE r.nombre = 'cliente'
                 ORDER BY u.id
                 OFFSET mod(v_numero - 1, 40)
                 LIMIT 1;

                SELECT COALESCE(SUM(m.sillas), 0)::INTEGER INTO v_cantidad
                  FROM mesas m
                 WHERE m.id = v_mesa_principal
                    OR (v_grupo AND m.id = v_mesa_secundaria);

                INSERT INTO reservaciones (cliente_id, cantidad, estado)
                VALUES (v_cliente_id, v_cantidad, 0)
                RETURNING id INTO v_reservacion_id;

                INSERT INTO horarios (mesa_id, reservacion_id, inicio, duracion)
                VALUES (v_mesa_principal, v_reservacion_id, v_inicio, INTERVAL '90 minutes');
                IF v_grupo THEN
                    INSERT INTO horarios (mesa_id, reservacion_id, inicio, duracion)
                    VALUES (v_mesa_secundaria, v_reservacion_id, v_inicio, INTERVAL '90 minutes');
                END IF;

                IF mod(v_numero, 10) = 0 THEN
                    UPDATE reservaciones SET estado = 3 WHERE id = v_reservacion_id;
                    CONTINUE;
                END IF;

                UPDATE reservaciones SET estado = 1 WHERE id = v_reservacion_id;
                IF v_pedido_historico THEN
                    SELECT u.id INTO v_mesero_id
                      FROM usuarios u
                      JOIN actuaciones a ON a.usuario_id = u.id
                      JOIN roles r ON r.id = a.rol_id
                     WHERE r.nombre = 'mesero'
                     ORDER BY u.id
                     OFFSET mod(v_numero - 1, 5)
                     LIMIT 1;

                    INSERT INTO pedidos (cliente_id, mesero_id)
                    VALUES (v_cliente_id, v_mesero_id)
                    RETURNING id INTO v_pedido_id;

                    v_cantidad_ordenes := 1 + mod(v_numero, 4);
                    FOR v_numero_orden IN 1..v_cantidad_ordenes LOOP
                        v_plato_id := 1 + mod((v_numero - 1) * 7 + v_numero_orden - 1, 24);
                        SELECT e.cocinero_id INTO v_cocinero_id
                          FROM (
                              SELECT es.cocinero_id,
                                     row_number() OVER (ORDER BY es.cocinero_id) - 1 AS posicion,
                                     count(*) OVER () AS total
                                FROM especialidades es
                               WHERE es.plato_id = v_plato_id
                          ) e
                         WHERE e.posicion = mod(v_numero + v_numero_orden, e.total);

                        INSERT INTO ordenes (plato_id, pedido_id, estado, cantidad, solicitado)
                        VALUES (
                            v_plato_id,
                            v_pedido_id,
                            0,
                            1 + mod(v_numero + v_numero_orden, 4),
                            (v_inicio + INTERVAL '30 minutes') AT TIME ZONE 'America/Bogota'
                        )
                        RETURNING id INTO v_orden_id;

                        INSERT INTO preparaciones (cocinero_id, orden_id)
                        VALUES (v_cocinero_id, v_orden_id);
                        UPDATE ordenes SET estado = 1 WHERE id = v_orden_id;
                        UPDATE ordenes SET estado = 2 WHERE id = v_orden_id;
                    END LOOP;
                END IF;
                UPDATE reservaciones SET estado = 2 WHERE id = v_reservacion_id;
            END LOOP;
        END LOOP;
    END IF;

    -- Dos mesas ocupadas con órdenes en los tres estados de demostración.
    SELECT u.id INTO v_cliente_id
      FROM usuarios u
      JOIN actuaciones a ON a.usuario_id = u.id
      JOIN roles r ON r.id = a.rol_id
     WHERE r.nombre = 'cliente'
     ORDER BY u.id LIMIT 1;
    INSERT INTO reservaciones (cliente_id, cantidad, estado)
    VALUES (v_cliente_id, 4, 0) RETURNING id INTO v_reservacion_id;
    INSERT INTO horarios (mesa_id, reservacion_id, inicio, duracion)
    VALUES (11, v_reservacion_id, v_ahora - INTERVAL '45 minutes', INTERVAL '90 minutes');
    UPDATE reservaciones SET estado = 1 WHERE id = v_reservacion_id;

    SELECT u.id INTO v_mesero_id
      FROM usuarios u
      JOIN actuaciones a ON a.usuario_id = u.id
      JOIN roles r ON r.id = a.rol_id
     WHERE r.nombre = 'mesero'
     ORDER BY u.id LIMIT 1;
    INSERT INTO pedidos (cliente_id, mesero_id)
    VALUES (v_cliente_id, v_mesero_id) RETURNING id INTO v_pedido_demo_1;

    SELECT u.id INTO v_cliente_id
      FROM usuarios u
      JOIN actuaciones a ON a.usuario_id = u.id
      JOIN roles r ON r.id = a.rol_id
     WHERE r.nombre = 'cliente'
     ORDER BY u.id OFFSET 1 LIMIT 1;
    INSERT INTO reservaciones (cliente_id, cantidad, estado)
    VALUES (v_cliente_id, 6, 0) RETURNING id INTO v_reservacion_id;
    INSERT INTO horarios (mesa_id, reservacion_id, inicio, duracion)
    VALUES (12, v_reservacion_id, v_ahora - INTERVAL '30 minutes', INTERVAL '90 minutes');
    UPDATE reservaciones SET estado = 1 WHERE id = v_reservacion_id;
    INSERT INTO pedidos (cliente_id, mesero_id)
    VALUES (v_cliente_id, v_mesero_id) RETURNING id INTO v_pedido_demo_2;

    FOR v_numero_orden IN 1..8 LOOP
        v_plato_id := v_numero_orden;
        IF v_numero_orden <= 5 THEN
            v_pedido_id := v_pedido_demo_1;
        ELSE
            v_pedido_id := v_pedido_demo_2;
        END IF;
        v_estado_orden := CASE
            WHEN v_numero_orden <= 5 THEN 0
            WHEN v_numero_orden <= 7 THEN 1
            ELSE 2
        END;

        INSERT INTO ordenes (plato_id, pedido_id, estado, cantidad, solicitado)
        VALUES (v_plato_id, v_pedido_id, 0, 1, now() - INTERVAL '5 minutes')
        RETURNING id INTO v_orden_id;

        IF v_estado_orden IN (1, 2) THEN
            SELECT e.cocinero_id INTO v_cocinero_id
              FROM (
                  SELECT es.cocinero_id,
                         row_number() OVER (ORDER BY es.cocinero_id) - 1 AS posicion,
                         count(*) OVER () AS total
                    FROM especialidades es
                   WHERE es.plato_id = v_plato_id
              ) e
             WHERE e.posicion = mod(v_numero_orden, e.total);
            INSERT INTO preparaciones (cocinero_id, orden_id)
            VALUES (v_cocinero_id, v_orden_id);
            UPDATE ordenes SET estado = 1 WHERE id = v_orden_id;
            IF v_estado_orden = 2 THEN
                UPDATE ordenes SET estado = 2 WHERE id = v_orden_id;
            END IF;
        END IF;
    END LOOP;

    -- Aviso próximo al maitre y otra reservación posterior para hoy.
    SELECT u.id INTO v_cliente_id
      FROM usuarios u
      JOIN actuaciones a ON a.usuario_id = u.id
      JOIN roles r ON r.id = a.rol_id
     WHERE r.nombre = 'cliente'
     ORDER BY u.id OFFSET 2 LIMIT 1;
    INSERT INTO reservaciones (cliente_id, cantidad, estado)
    VALUES (v_cliente_id, 2, 0) RETURNING id INTO v_reservacion_id;
    INSERT INTO horarios (mesa_id, reservacion_id, inicio, duracion)
    VALUES (13, v_reservacion_id, v_ahora + INTERVAL '15 minutes', INTERVAL '90 minutes');

    INSERT INTO reservaciones (cliente_id, cantidad, estado)
    VALUES (v_cliente_id, 4, 0) RETURNING id INTO v_reservacion_id;
    -- Después de las 23:00, el siguiente horario futuro cae necesariamente mañana.
    v_inicio := CASE
        WHEN v_ahora::TIME < TIME '23:00'
            THEN date_trunc('day', v_ahora) + INTERVAL '23 hours'
        ELSE v_ahora + INTERVAL '3 hours'
    END;
    INSERT INTO horarios (mesa_id, reservacion_id, inicio, duracion)
    VALUES (14, v_reservacion_id, v_inicio, INTERVAL '90 minutes');

    -- Reservaciones en los próximos 21 días, una fecha distinta por fila.
    FOR v_numero_orden IN 1..21 LOOP
        v_fecha_futura := CURRENT_DATE + v_numero_orden;
        v_hora_futura := TIME '12:00' + mod(v_numero_orden - 1, 5) * INTERVAL '2 hours';
        SELECT u.id INTO v_cliente_id
          FROM usuarios u
          JOIN actuaciones a ON a.usuario_id = u.id
          JOIN roles r ON r.id = a.rol_id
         WHERE r.nombre = 'cliente'
         ORDER BY u.id OFFSET mod(v_numero_orden - 1, 40) LIMIT 1;
        v_mesa_principal := 1 + mod(v_numero_orden - 1, 15);
        SELECT sillas INTO v_cantidad FROM mesas WHERE id = v_mesa_principal;
        INSERT INTO reservaciones (cliente_id, cantidad, estado)
        VALUES (v_cliente_id, v_cantidad, 0) RETURNING id INTO v_reservacion_id;
        INSERT INTO horarios (mesa_id, reservacion_id, inicio, duracion)
        VALUES (v_mesa_principal, v_reservacion_id,
                v_fecha_futura + v_hora_futura, INTERVAL '90 minutes');
    END LOOP;

    -- Fechas desde 2027-01-15 para poblar horarios_3, incluso en ejecuciones posteriores.
    v_fecha_futura := GREATEST(DATE '2027-01-15', CURRENT_DATE + 22);
    FOR v_numero_orden IN 1..16 LOOP
        v_hora_futura := TIME '12:00' + mod(v_numero_orden - 1, 5) * INTERVAL '2 hours';
        SELECT u.id INTO v_cliente_id
          FROM usuarios u
          JOIN actuaciones a ON a.usuario_id = u.id
          JOIN roles r ON r.id = a.rol_id
         WHERE r.nombre = 'cliente'
         ORDER BY u.id OFFSET mod(v_numero_orden, 40) LIMIT 1;
        v_mesa_principal := 1 + mod(v_numero_orden + 4, 15);
        SELECT sillas INTO v_cantidad FROM mesas WHERE id = v_mesa_principal;
        INSERT INTO reservaciones (cliente_id, cantidad, estado)
        VALUES (v_cliente_id, v_cantidad, 0) RETURNING id INTO v_reservacion_id;
        INSERT INTO horarios (mesa_id, reservacion_id, inicio, duracion)
        VALUES (v_mesa_principal, v_reservacion_id,
                v_fecha_futura + (v_numero_orden - 1) * 7 + v_hora_futura,
                INTERVAL '90 minutes');
    END LOOP;
END;
$$;

COMMIT;

SELECT 'roles' AS tabla, COUNT(*) AS filas FROM roles
UNION ALL SELECT 'tipos', COUNT(*) FROM tipos
UNION ALL SELECT 'usuarios', COUNT(*) FROM usuarios
UNION ALL SELECT 'actuaciones', COUNT(*) FROM actuaciones
UNION ALL SELECT 'mesas', COUNT(*) FROM mesas
UNION ALL SELECT 'platos', COUNT(*) FROM platos
UNION ALL SELECT 'especialidades', COUNT(*) FROM especialidades
UNION ALL SELECT 'reservaciones', COUNT(*) FROM reservaciones
UNION ALL SELECT 'horarios', COUNT(*) FROM horarios
UNION ALL SELECT 'horarios_1', COUNT(*) FROM horarios_1
UNION ALL SELECT 'horarios_2', COUNT(*) FROM horarios_2
UNION ALL SELECT 'horarios_3', COUNT(*) FROM horarios_3
UNION ALL SELECT 'pedidos', COUNT(*) FROM pedidos
UNION ALL SELECT 'ordenes', COUNT(*) FROM ordenes
UNION ALL SELECT 'preparaciones', COUNT(*) FROM preparaciones
ORDER BY tabla;
