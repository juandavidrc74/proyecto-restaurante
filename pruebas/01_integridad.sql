-- Ejecutar conectado a restaurante_proyecto con psql, con la base recién reconstruida
-- con sql/reconstruir.sql y sin datos, porque crea sus propios catálogos. No conserva datos.
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL TIME ZONE 'UTC';

CREATE TEMP TABLE resultados_integridad (
    caso TEXT NOT NULL,
    esperado TEXT NOT NULL,
    obtenido TEXT NOT NULL,
    estado TEXT NOT NULL
) ON COMMIT DROP;

CREATE FUNCTION pg_temp.probar(p_caso TEXT, p_esperado TEXT, p_sql TEXT)
RETURNS VOID
LANGUAGE plpgsql
AS $$
DECLARE
    v_obtenido TEXT;
    v_estado TEXT;
BEGIN
    BEGIN
        EXECUTE p_sql;
        SET CONSTRAINTS ALL IMMEDIATE;
        RAISE EXCEPTION '__CASO_EJECUTADO__';
    EXCEPTION WHEN OTHERS THEN
        IF SQLERRM = '__CASO_EJECUTADO__' THEN
            v_obtenido := 'ÉXITO';
        ELSE
            v_obtenido := 'RECHAZO: ' || SQLERRM;
        END IF;
    END;

    IF (p_esperado = 'ÉXITO' AND v_obtenido = 'ÉXITO')
       OR (p_esperado = 'RECHAZO' AND v_obtenido LIKE 'RECHAZO:%') THEN
        v_estado := 'APROBADO';
    ELSE
        v_estado := 'FALLIDO';
    END IF;
    INSERT INTO resultados_integridad VALUES (p_caso, p_esperado, v_obtenido, v_estado);
END;
$$;

-- Catálogos y entidades de referencia; cada caso posterior revierte sus datos.
INSERT INTO roles (id, nombre) VALUES
    (910001, 'cliente'), (910002, 'cocinero'), (910003, 'mesero');
INSERT INTO tipos (id, nombre) VALUES
    (910001, 'entrada'), (910002, 'plato fuerte'), (910003, 'postre'), (910004, 'bebida');
INSERT INTO usuarios (id, nombre) VALUES
    (910001, 'Cliente de prueba'), (910002, 'Cocinero de prueba'), (910003, 'Mesero de prueba');
INSERT INTO actuaciones (id, rol_id, usuario_id) VALUES
    (910001, 910002, 910002), (910002, 910003, 910003);
INSERT INTO mesas (id, sillas) VALUES (910001, 4), (910002, 4);
INSERT INTO platos (id, tipo_id, nombre, descripcion, tiempo, precio) VALUES
    (910001, 910001, 'Plato de prueba', 'Descripción', INTERVAL '15 minutes', 10),
    (910002, 910001, 'Segundo plato de prueba', 'Descripción', INTERVAL '20 minutes', 12);
-- Declarativas: validaciones positivas y negativas.
SELECT pg_temp.probar('usuario nombre no vacío', 'RECHAZO',
    $$INSERT INTO usuarios (nombre) VALUES ('   ')$$);
SELECT pg_temp.probar('clave y fecha_clave juntas', 'RECHAZO',
    $$INSERT INTO usuarios (nombre, clave) VALUES ('Usuario inválido', decode('01','hex'))$$);
SELECT pg_temp.probar('nombre de rol único', 'RECHAZO',
    $$INSERT INTO roles (nombre) VALUES ('cliente')$$);
SELECT pg_temp.probar('nombre de tipo único', 'RECHAZO',
    $$INSERT INTO tipos (nombre) VALUES ('entrada')$$);
SELECT pg_temp.probar('categoría de tipo limitada', 'RECHAZO',
    $$INSERT INTO tipos (nombre) VALUES ('guarnición')$$);
SELECT pg_temp.probar('actuación usuario-rol única', 'RECHAZO',
    $$INSERT INTO actuaciones (rol_id, usuario_id) VALUES (910002, 910002)$$);
SELECT pg_temp.probar('precio de plato no puede ser NaN', 'RECHAZO',
    $$INSERT INTO platos (tipo_id,nombre,descripcion,tiempo,precio) VALUES (910001,'Precio NaN','x',INTERVAL '1 minute','NaN')$$);
SELECT pg_temp.probar('precio de plato no negativo', 'RECHAZO',
    $$INSERT INTO platos (tipo_id,nombre,descripcion,tiempo,precio) VALUES (910001,'Precio negativo','x',INTERVAL '1 minute',-1)$$);
SELECT pg_temp.probar('tiempo de plato positivo', 'RECHAZO',
    $$INSERT INTO platos (tipo_id,nombre,descripcion,tiempo,precio) VALUES (910001,'Tiempo cero','x',INTERVAL '0',1)$$);
SELECT pg_temp.probar('nombre de plato único', 'RECHAZO',
    $$INSERT INTO platos (tipo_id,nombre,descripcion,tiempo,precio) VALUES (910001,'Plato de prueba','x',INTERVAL '1 minute',1)$$);
SELECT pg_temp.probar('mesas con sillas positivas', 'RECHAZO',
    $$INSERT INTO mesas (sillas) VALUES (0)$$);
SELECT pg_temp.probar('identificador de mesa único', 'RECHAZO',
    $$INSERT INTO mesas (id, sillas) VALUES (910001, 4)$$);
SELECT pg_temp.probar('cantidad de reservación positiva', 'RECHAZO',
    $$INSERT INTO reservaciones (cliente_id,cantidad,estado) VALUES (910001,0,0)$$);
SELECT pg_temp.probar('estado de reservación dentro del rango', 'RECHAZO',
    $$INSERT INTO reservaciones (cliente_id,cantidad,estado) VALUES (910001,1,4)$$);
SELECT pg_temp.probar('cantidad de orden positiva', 'RECHAZO',
    $caso$DO $bloque$ BEGIN
      INSERT INTO pedidos (id,cliente_id,mesero_id) VALUES (991010,910001,910003);
      INSERT INTO reservaciones (id,cliente_id,cantidad,estado) VALUES (910026,910001,2,0);
      INSERT INTO horarios VALUES (991030,910001,910026,'2026-11-10 10:00',INTERVAL '1 hour');
      INSERT INTO ordenes (plato_id,pedido_id,cantidad,solicitado)
        VALUES (910001,991010,0,'2026-11-10 10:30+00');
    END; $bloque$;$caso$);
SELECT pg_temp.probar('especialidad exige rol cocinero', 'RECHAZO',
    $$INSERT INTO especialidades (cocinero_id,plato_id) VALUES (910001,910001)$$);
SELECT pg_temp.probar('cocinero especializado prepara orden solicitada', 'ÉXITO',
$caso$DO $bloque$ BEGIN
  INSERT INTO reservaciones (id,cliente_id,cantidad,estado) VALUES (910027,910001,2,0);
  INSERT INTO pedidos (id,cliente_id,mesero_id) VALUES (991020,910001,910003);
  INSERT INTO horarios VALUES (991031,910001,910027,'2026-11-10 10:00',INTERVAL '1 hour');
  INSERT INTO ordenes (id,plato_id,pedido_id,cantidad,solicitado)
    VALUES (991020,910001,991020,1,'2026-11-10 10:30+00');
  INSERT INTO especialidades (cocinero_id,plato_id) VALUES (910002,910001);
  INSERT INTO preparaciones (cocinero_id,orden_id) VALUES (910002,991020);
  UPDATE ordenes SET estado=1 WHERE id=991020;
END; $bloque$;$caso$);
SELECT pg_temp.probar('no borrar preparación de orden preparada', 'RECHAZO',
$caso$DO $bloque$ BEGIN
  INSERT INTO reservaciones (id,cliente_id,cantidad,estado) VALUES (910028,910001,2,0);
  INSERT INTO pedidos (id,cliente_id,mesero_id) VALUES (991021,910001,910003);
  INSERT INTO horarios VALUES (991032,910001,910028,'2026-11-10 10:00',INTERVAL '1 hour');
  INSERT INTO ordenes (id,plato_id,pedido_id,cantidad,solicitado)
    VALUES (991021,910001,991021,1,'2026-11-10 10:30+00');
  INSERT INTO especialidades (cocinero_id,plato_id) VALUES (910002,910001);
  INSERT INTO preparaciones (cocinero_id,orden_id) VALUES (910002,991021);
  UPDATE ordenes SET estado=1 WHERE id=991021;
  DELETE FROM preparaciones WHERE orden_id=991021;
END; $bloque$;$caso$);

-- Cada expresión DO es un único comando dinámico. El helper revierte al salir.
SELECT pg_temp.probar('cruce en la misma mesa se rechaza', 'RECHAZO',
$caso$DO $bloque$ BEGIN
  INSERT INTO reservaciones (id,cliente_id,cantidad,estado) VALUES (910001,910001,2,0);
  INSERT INTO horarios (id,mesa_id,reservacion_id,inicio,duracion) VALUES
    (991001,910001,910001,'2026-11-10 10:00',INTERVAL '1 hour');
  INSERT INTO reservaciones (id,cliente_id,cantidad,estado) VALUES (910002,910001,2,0);
  INSERT INTO horarios (id,mesa_id,reservacion_id,inicio,duracion) VALUES
    (991002,910001,910002,'2026-11-10 11:00',INTERVAL '1 hour');
END; $bloque$;$caso$);
SELECT pg_temp.probar('ventanas contiguas permitidas', 'ÉXITO',
$caso$DO $bloque$ BEGIN
  INSERT INTO reservaciones (id,cliente_id,cantidad,estado) VALUES (910003,910001,2,0);
  INSERT INTO horarios VALUES (991003,910001,910003,'2026-11-10 10:00',INTERVAL '1 hour');
  INSERT INTO reservaciones (id,cliente_id,cantidad,estado) VALUES (910004,910001,2,0);
  INSERT INTO horarios VALUES (991004,910001,910004,'2026-11-10 12:00',INTERVAL '1 hour');
END; $bloque$;$caso$);
SELECT pg_temp.probar('cruce con reservación cancelada permitido', 'ÉXITO',
$caso$DO $bloque$ BEGIN
  INSERT INTO reservaciones (id,cliente_id,cantidad,estado) VALUES (910005,910001,2,0);
  INSERT INTO horarios VALUES (991005,910001,910005,'2026-11-10 10:00',INTERVAL '1 hour');
  UPDATE reservaciones SET estado=3 WHERE id=910005;
  INSERT INTO reservaciones (id,cliente_id,cantidad,estado) VALUES (910006,910001,2,0);
  INSERT INTO horarios VALUES (991006,910001,910006,'2026-11-10 10:30',INTERVAL '1 hour');
END; $bloque$;$caso$);
SELECT pg_temp.probar('superar cupo se rechaza', 'RECHAZO',
$caso$DO $bloque$ BEGIN
  INSERT INTO reservaciones (id,cliente_id,cantidad,estado) VALUES (910007,910001,9,0);
  INSERT INTO horarios VALUES (991007,910001,910007,'2026-11-10 10:00',INTERVAL '1 hour');
END; $bloque$;$caso$);
SELECT pg_temp.probar('cambiar cantidad revalida las sillas', 'RECHAZO',
$caso$DO $bloque$ BEGIN
  INSERT INTO reservaciones (id,cliente_id,cantidad,estado) VALUES (910024,910001,2,0);
  INSERT INTO horarios VALUES (991028,910001,910024,'2026-11-10 10:00',INTERVAL '1 hour');
  UPDATE reservaciones SET cantidad=9 WHERE id=910024;
END; $bloque$;$caso$);
SELECT pg_temp.probar('sillas insuficientes se rechazan diferido', 'RECHAZO',
$caso$DO $bloque$ BEGIN
  INSERT INTO reservaciones (id,cliente_id,cantidad,estado) VALUES (910008,910001,5,0);
  INSERT INTO horarios VALUES (991008,910001,910008,'2026-11-10 10:00',INTERVAL '1 hour');
END; $bloque$;$caso$);
SELECT pg_temp.probar('dos mesas de una reservación se cuentan una vez', 'ÉXITO',
$caso$DO $bloque$ BEGIN
  INSERT INTO reservaciones (id,cliente_id,cantidad,estado) VALUES (910009,910001,8,0);
  INSERT INTO horarios VALUES
    (991009,910001,910009,'2026-11-10 10:00',INTERVAL '1 hour'),
    (991010,910002,910009,'2026-11-10 10:00',INTERVAL '1 hour');
END; $bloque$;$caso$);
SELECT pg_temp.probar('duración cero se rechaza', 'RECHAZO',
    $caso$DO $bloque$ BEGIN
      INSERT INTO reservaciones (id,cliente_id,cantidad,estado) VALUES (910010,910001,2,0);
      INSERT INTO horarios VALUES (991011,910001,910010,'2026-11-10 10:00',INTERVAL '0');
    END; $bloque$;$caso$);
SELECT pg_temp.probar('duración negativa se rechaza', 'RECHAZO',
    $caso$DO $bloque$ BEGIN
      INSERT INTO reservaciones (id,cliente_id,cantidad,estado) VALUES (910010,910001,2,0);
      INSERT INTO horarios VALUES (991012,910001,910010,'2026-11-10 10:00',INTERVAL '-1 minute');
    END; $bloque$;$caso$);
SELECT pg_temp.probar('duración de dos horas se rechaza', 'RECHAZO',
    $caso$DO $bloque$ BEGIN
      INSERT INTO reservaciones (id,cliente_id,cantidad,estado) VALUES (910010,910001,2,0);
      INSERT INTO horarios VALUES (991013,910001,910010,'2026-11-10 10:00',INTERVAL '2 hours');
    END; $bloque$;$caso$);
SELECT pg_temp.probar('duración 1:59 se permite', 'ÉXITO',
    $caso$DO $bloque$ BEGIN
      INSERT INTO reservaciones (id,cliente_id,cantidad,estado) VALUES (910010,910001,2,0);
      INSERT INTO horarios VALUES (991014,910001,910010,'2026-11-10 10:00',INTERVAL '1 hour 59 minutes');
    END; $bloque$;$caso$);
SELECT pg_temp.probar('id repetido entre particiones se rechaza', 'RECHAZO',
$caso$DO $bloque$ BEGIN
  INSERT INTO reservaciones (id,cliente_id,cantidad,estado) VALUES (910011,910001,2,0);
  INSERT INTO horarios VALUES (991015,910001,910011,'2026-09-20',INTERVAL '1 hour');
  INSERT INTO horarios VALUES (991015,910001,910011,'2026-10-20',INTERVAL '1 hour');
END; $bloque$;$caso$);
SELECT pg_temp.probar('mover horario entre particiones válido', 'ÉXITO',
$caso$DO $bloque$ BEGIN
  INSERT INTO reservaciones (id,cliente_id,cantidad,estado) VALUES (910012,910001,2,0);
  INSERT INTO horarios VALUES (991016,910001,910012,'2026-09-20',INTERVAL '1 hour');
  UPDATE horarios SET inicio='2026-10-20' WHERE id=991016;
END; $bloque$;$caso$);
SELECT pg_temp.probar('mover horario que crea cruce se rechaza', 'RECHAZO',
$caso$DO $bloque$ BEGIN
  INSERT INTO reservaciones (id,cliente_id,cantidad,estado) VALUES (910013,910001,2,0);
  INSERT INTO horarios VALUES (991017,910001,910013,'2026-10-20 10:00',INTERVAL '1 hour');
  INSERT INTO reservaciones (id,cliente_id,cantidad,estado) VALUES (910014,910001,2,0);
  INSERT INTO horarios VALUES (991018,910001,910014,'2026-09-20 14:00',INTERVAL '1 hour');
  UPDATE horarios SET inicio='2026-10-20 11:00' WHERE id=991018;
END; $bloque$;$caso$);
SELECT pg_temp.probar('reducir sillas con asignación se rechaza', 'RECHAZO',
$caso$DO $bloque$ BEGIN
  INSERT INTO reservaciones (id,cliente_id,cantidad,estado) VALUES (910015,910001,4,0);
  INSERT INTO horarios VALUES (991019,910001,910015,'2026-10-21',INTERVAL '1 hour');
  UPDATE mesas SET sillas=3 WHERE id=910001;
END; $bloque$;$caso$);
SELECT pg_temp.probar('quitar rol de cocinero con historial se rechaza', 'RECHAZO',
$caso$DO $bloque$ BEGIN
  INSERT INTO especialidades (cocinero_id,plato_id) VALUES (910002,910001);
  DELETE FROM actuaciones WHERE usuario_id=910002 AND rol_id=910002;
END; $bloque$;$caso$);
SELECT pg_temp.probar('pedido requiere rol de mesero', 'RECHAZO',
    $$INSERT INTO pedidos (cliente_id,mesero_id) VALUES (910001,910001)$$);
SELECT pg_temp.probar('orden sin reservación vigente se rechaza', 'RECHAZO',
$caso$DO $bloque$ BEGIN
  INSERT INTO pedidos (id,cliente_id,mesero_id) VALUES (991001,910001,910003);
  INSERT INTO ordenes (id,plato_id,pedido_id,cantidad,solicitado)
    VALUES (991001,910001,991001,1,'2026-11-10 10:00+00');
END; $bloque$;$caso$);
SELECT pg_temp.probar('salto de estado de orden se rechaza', 'RECHAZO',
$caso$DO $bloque$ BEGIN
  INSERT INTO pedidos (id,cliente_id,mesero_id) VALUES (991002,910001,910003);
  INSERT INTO reservaciones (id,cliente_id,cantidad,estado) VALUES (910016,910001,2,0);
  INSERT INTO horarios VALUES (991020,910001,910016,'2026-11-10 10:00',INTERVAL '1 hour');
  INSERT INTO ordenes (id,plato_id,pedido_id,cantidad,solicitado)
    VALUES (991002,910001,991002,1,'2026-11-10 10:30+00');
  UPDATE ordenes SET estado=2 WHERE id=991002;
END; $bloque$;$caso$);
SELECT pg_temp.probar('orden no pasa a preparada sin preparación', 'RECHAZO',
$caso$DO $bloque$ BEGIN
  INSERT INTO pedidos (id,cliente_id,mesero_id) VALUES (991003,910001,910003);
  INSERT INTO reservaciones (id,cliente_id,cantidad,estado) VALUES (910017,910001,2,0);
  INSERT INTO horarios VALUES (991021,910001,910017,'2026-11-10 10:00',INTERVAL '1 hour');
  INSERT INTO ordenes (id,plato_id,pedido_id,cantidad,solicitado)
    VALUES (991003,910001,991003,1,'2026-11-10 10:30+00');
  UPDATE ordenes SET estado=1 WHERE id=991003;
END; $bloque$;$caso$);
SELECT pg_temp.probar('preparación requiere especialidad del plato', 'RECHAZO',
$caso$DO $bloque$ BEGIN
  INSERT INTO pedidos (id,cliente_id,mesero_id) VALUES (991004,910001,910003);
  INSERT INTO reservaciones (id,cliente_id,cantidad,estado) VALUES (910018,910001,2,0);
  INSERT INTO horarios VALUES (991022,910001,910018,'2026-11-10 10:00',INTERVAL '1 hour');
  INSERT INTO ordenes (id,plato_id,pedido_id,cantidad,solicitado)
    VALUES (991004,910001,991004,1,'2026-11-10 10:30+00');
  INSERT INTO preparaciones (cocinero_id,orden_id) VALUES (910002,991004);
END; $bloque$;$caso$);
SELECT pg_temp.probar('retroceso de estado de orden se rechaza', 'RECHAZO',
$caso$DO $bloque$ BEGIN
  INSERT INTO pedidos (id,cliente_id,mesero_id) VALUES (991005,910001,910003);
  INSERT INTO reservaciones (id,cliente_id,cantidad,estado) VALUES (910019,910001,2,0);
  INSERT INTO horarios VALUES (991023,910001,910019,'2026-11-10 10:00',INTERVAL '1 hour');
  INSERT INTO ordenes (id,plato_id,pedido_id,cantidad,solicitado,estado)
    VALUES (991005,910001,991005,1,'2026-11-10 10:30+00',0);
  INSERT INTO especialidades (cocinero_id,plato_id) VALUES (910002,910001);
  INSERT INTO preparaciones (cocinero_id,orden_id) VALUES (910002,991005);
  UPDATE ordenes SET estado=1 WHERE id=991005;
  UPDATE ordenes SET estado=0 WHERE id=991005;
END; $bloque$;$caso$);
SELECT pg_temp.probar('transición reservada a ocupada permitida', 'ÉXITO',
$caso$DO $bloque$ BEGIN
  INSERT INTO reservaciones (id,cliente_id,cantidad,estado) VALUES (910020,910001,2,0);
  INSERT INTO horarios VALUES (991024,910001,910020,'2026-11-10 10:00',INTERVAL '1 hour');
  UPDATE reservaciones SET estado=1 WHERE id=910020;
END; $bloque$;$caso$);
SELECT pg_temp.probar('estado final liberada no admite transición', 'RECHAZO',
$caso$DO $bloque$ BEGIN
  INSERT INTO reservaciones (id,cliente_id,cantidad,estado) VALUES (910021,910001,2,0);
  INSERT INTO horarios VALUES (991025,910001,910021,'2026-11-10 10:00',INTERVAL '1 hour');
  UPDATE reservaciones SET estado=1 WHERE id=910021;
  UPDATE reservaciones SET estado=2 WHERE id=910021;
  UPDATE reservaciones SET estado=0 WHERE id=910021;
END; $bloque$;$caso$);
SELECT pg_temp.probar('estado final cancelada no admite transición', 'RECHAZO',
$caso$DO $bloque$ BEGIN
  INSERT INTO reservaciones (id,cliente_id,cantidad,estado) VALUES (910025,910001,2,0);
  INSERT INTO horarios VALUES (991029,910001,910025,'2026-11-10 10:00',INTERVAL '1 hour');
  UPDATE reservaciones SET estado=3 WHERE id=910025;
  UPDATE reservaciones SET estado=1 WHERE id=910025;
END; $bloque$;$caso$);
SELECT pg_temp.probar('mesa de pedido con dos mesas devuelve la menor', 'ÉXITO',
$caso$DO $bloque$ DECLARE v_mesa INTEGER; BEGIN
  INSERT INTO pedidos (id,cliente_id,mesero_id) VALUES (991006,910001,910003);
  INSERT INTO reservaciones (id,cliente_id,cantidad,estado) VALUES (910022,910001,2,0),(910023,910001,2,0);
  INSERT INTO horarios VALUES
    (991026,910002,910022,'2026-11-10 10:00',INTERVAL '1 hour'),
    (991027,910001,910023,'2026-11-10 10:00',INTERVAL '1 hour');
  INSERT INTO ordenes (id,plato_id,pedido_id,cantidad,solicitado)
    VALUES (991006,910001,991006,1,'2026-11-10 10:30+00');
  SELECT mesa_de_pedido(991006) INTO v_mesa;
  IF v_mesa <> 910001 THEN RAISE EXCEPTION 'Se esperaba la mesa menor.'; END IF;
END; $bloque$;$caso$);

-- un pedido conserva su asociación a la reservación y al horario original.
SELECT pg_temp.probar('cambiar inicio de horario con pedidos se rechaza', 'RECHAZO',
$caso$DO $bloque$ BEGIN
  INSERT INTO reservaciones VALUES (911001,910001,2,0);
  INSERT INTO horarios VALUES (992001,910001,911001,'2026-11-11 10:00',INTERVAL '1 hour');
  INSERT INTO pedidos VALUES (992001,910001,910003);
  INSERT INTO ordenes (id,plato_id,pedido_id,cantidad,solicitado)
    VALUES (992001,910001,992001,1,'2026-11-11 10:30+00');
  UPDATE horarios SET inicio='2026-11-11 11:00' WHERE id=992001;
END; $bloque$;$caso$);
SELECT pg_temp.probar('borrar y reponer horario con pedidos se rechaza', 'RECHAZO',
$caso$DO $bloque$ BEGIN
  INSERT INTO reservaciones VALUES (911002,910001,2,0);
  INSERT INTO horarios VALUES (992002,910001,911002,'2026-11-11 10:00',INTERVAL '1 hour');
  INSERT INTO pedidos VALUES (992002,910001,910003);
  INSERT INTO ordenes (id,plato_id,pedido_id,cantidad,solicitado)
    VALUES (992002,910001,992002,1,'2026-11-11 10:30+00');
  DELETE FROM horarios WHERE id=992002;
  INSERT INTO horarios VALUES (992003,910001,911002,'2026-11-12 10:00',INTERVAL '1 hour');
END; $bloque$;$caso$);
SELECT pg_temp.probar('cambiar mesa de horario con pedidos se rechaza', 'RECHAZO',
$caso$DO $bloque$ BEGIN
  INSERT INTO reservaciones VALUES (911003,910001,2,0);
  INSERT INTO horarios VALUES (992004,910001,911003,'2026-11-11 10:00',INTERVAL '1 hour');
  INSERT INTO pedidos VALUES (992003,910001,910003);
  INSERT INTO ordenes (id,plato_id,pedido_id,cantidad,solicitado)
    VALUES (992003,910001,992003,1,'2026-11-11 10:30+00');
  UPDATE horarios SET mesa_id=910002 WHERE id=992004;
END; $bloque$;$caso$);
SELECT pg_temp.probar('cambiar reservación de horario con pedidos se rechaza', 'RECHAZO',
$caso$DO $bloque$ BEGIN
  INSERT INTO reservaciones VALUES (911004,910001,2,0),(911005,910001,2,0);
  INSERT INTO horarios VALUES (992005,910001,911004,'2026-11-11 10:00',INTERVAL '1 hour');
  INSERT INTO pedidos VALUES (992004,910001,910003);
  INSERT INTO ordenes (id,plato_id,pedido_id,cantidad,solicitado)
    VALUES (992004,910001,992004,1,'2026-11-11 10:30+00');
  UPDATE horarios SET reservacion_id=911005 WHERE id=992005;
END; $bloque$;$caso$);
SELECT pg_temp.probar('cambiar cliente de reservación con pedidos se rechaza', 'RECHAZO',
$caso$DO $bloque$ BEGIN
  INSERT INTO reservaciones VALUES (911006,910001,2,0);
  INSERT INTO horarios VALUES (992006,910001,911006,'2026-11-11 10:00',INTERVAL '1 hour');
  INSERT INTO pedidos VALUES (992005,910001,910003);
  INSERT INTO ordenes (id,plato_id,pedido_id,cantidad,solicitado)
    VALUES (992005,910001,992005,1,'2026-11-11 10:30+00');
  UPDATE reservaciones SET cliente_id=910002 WHERE id=911006;
END; $bloque$;$caso$);
SELECT pg_temp.probar('orden no cambia solicitado', 'RECHAZO',
$caso$DO $bloque$ BEGIN
  INSERT INTO reservaciones VALUES (911007,910001,2,0);
  INSERT INTO horarios VALUES (992007,910001,911007,'2026-11-11 10:00',INTERVAL '1 hour');
  INSERT INTO pedidos VALUES (992006,910001,910003);
  INSERT INTO ordenes (id,plato_id,pedido_id,cantidad,solicitado)
    VALUES (992006,910001,992006,1,'2026-11-11 10:30+00');
  UPDATE ordenes SET solicitado='2026-11-11 10:31+00' WHERE id=992006;
END; $bloque$;$caso$);
SELECT pg_temp.probar('orden no cambia pedido_id', 'RECHAZO',
$caso$DO $bloque$ BEGIN
  INSERT INTO reservaciones VALUES (911008,910001,2,0);
  INSERT INTO horarios VALUES (992008,910001,911008,'2026-11-11 10:00',INTERVAL '1 hour');
  INSERT INTO pedidos VALUES (992007,910001,910003),(992008,910001,910003);
  INSERT INTO ordenes (id,plato_id,pedido_id,cantidad,solicitado)
    VALUES (992007,910001,992007,1,'2026-11-11 10:30+00');
  UPDATE ordenes SET pedido_id=992008 WHERE id=992007;
END; $bloque$;$caso$);
SELECT pg_temp.probar('pedido no cambia cliente con órdenes', 'RECHAZO',
$caso$DO $bloque$ BEGIN
  INSERT INTO reservaciones VALUES (911009,910001,2,0);
  INSERT INTO horarios VALUES (992009,910001,911009,'2026-11-11 10:00',INTERVAL '1 hour');
  INSERT INTO pedidos VALUES (992009,910001,910003);
  INSERT INTO ordenes (id,plato_id,pedido_id,cantidad,solicitado)
    VALUES (992009,910001,992009,1,'2026-11-11 10:30+00');
  UPDATE pedidos SET cliente_id=910002 WHERE id=992009;
END; $bloque$;$caso$);
SELECT pg_temp.probar('cancelar reservación con pedidos se rechaza', 'RECHAZO',
$caso$DO $bloque$ BEGIN
  INSERT INTO reservaciones VALUES (911010,910001,2,0);
  INSERT INTO horarios VALUES (992010,910001,911010,'2026-11-11 10:00',INTERVAL '1 hour');
  INSERT INTO pedidos VALUES (992010,910001,910003);
  INSERT INTO ordenes (id,plato_id,pedido_id,cantidad,solicitado)
    VALUES (992010,910001,992010,1,'2026-11-11 10:30+00');
  UPDATE reservaciones SET estado=3 WHERE id=911010;
END; $bloque$;$caso$);
SELECT pg_temp.probar('cancelar reservación sin pedidos se permite', 'ÉXITO',
$caso$DO $bloque$ BEGIN
  INSERT INTO reservaciones VALUES (911011,910001,2,0);
  INSERT INTO horarios VALUES (992011,910001,911011,'2026-11-11 10:00',INTERVAL '1 hour');
  UPDATE reservaciones SET estado=3 WHERE id=911011;
END; $bloque$;$caso$);
SELECT pg_temp.probar('liberar con pedidos conserva mesa derivada', 'ÉXITO',
$caso$DO $bloque$ DECLARE v_mesa INTEGER; BEGIN
  INSERT INTO reservaciones VALUES (911012,910001,2,0);
  INSERT INTO horarios VALUES (992012,910001,911012,'2026-11-11 10:00',INTERVAL '1 hour');
  INSERT INTO pedidos VALUES (992012,910001,910003);
  INSERT INTO ordenes (id,plato_id,pedido_id,cantidad,solicitado)
    VALUES (992012,910001,992012,1,'2026-11-11 10:30+00');
  UPDATE reservaciones SET estado=1 WHERE id=911012;
  UPDATE reservaciones SET estado=2 WHERE id=911012;
  SELECT mesa_de_pedido(992012) INTO v_mesa;
  IF v_mesa <> 910001 THEN RAISE EXCEPTION 'La mesa del pedido debe conservarse.'; END IF;
END; $bloque$;$caso$);
SELECT pg_temp.probar('cambiar duración de horario con pedidos se permite', 'ÉXITO',
$caso$DO $bloque$ BEGIN
  INSERT INTO reservaciones VALUES (911013,910001,2,0);
  INSERT INTO horarios VALUES (992013,910001,911013,'2026-11-11 10:00',INTERVAL '1 hour');
  INSERT INTO pedidos VALUES (992013,910001,910003);
  INSERT INTO ordenes (id,plato_id,pedido_id,cantidad,solicitado)
    VALUES (992013,910001,992013,1,'2026-11-11 10:30+00');
  UPDATE horarios SET duracion=INTERVAL '90 minutes' WHERE id=992013;
END; $bloque$;$caso$);
SELECT pg_temp.probar('cambiar cliente de reservación sin pedidos se permite', 'ÉXITO',
$caso$DO $bloque$ BEGIN
  INSERT INTO reservaciones VALUES (911014,910001,2,0);
  INSERT INTO horarios VALUES (992014,910001,911014,'2026-11-11 10:00',INTERVAL '1 hour');
  UPDATE reservaciones SET cliente_id=910002 WHERE id=911014;
END; $bloque$;$caso$);

-- solo las órdenes solicitadas y sin preparaciones son editables o borrables.
SELECT pg_temp.probar('cambiar plato y cantidad de orden solicitada', 'ÉXITO',
$caso$DO $bloque$ BEGIN
  INSERT INTO reservaciones VALUES (911020,910001,2,0);
  INSERT INTO horarios VALUES (992020,910001,911020,'2026-11-11 10:00',INTERVAL '1 hour');
  INSERT INTO pedidos VALUES (992020,910001,910003);
  INSERT INTO ordenes (id,plato_id,pedido_id,cantidad,solicitado)
    VALUES (992020,910001,992020,1,'2026-11-11 10:30+00');
  UPDATE ordenes SET plato_id=910002,cantidad=3 WHERE id=992020;
END; $bloque$;$caso$);
SELECT pg_temp.probar('no cambiar cantidad de orden preparada', 'RECHAZO',
$caso$DO $bloque$ BEGIN
  INSERT INTO reservaciones VALUES (911021,910001,2,0);
  INSERT INTO horarios VALUES (992021,910001,911021,'2026-11-11 10:00',INTERVAL '1 hour');
  INSERT INTO pedidos VALUES (992021,910001,910003);
  INSERT INTO ordenes (id,plato_id,pedido_id,cantidad,solicitado)
    VALUES (992021,910001,992021,1,'2026-11-11 10:30+00');
  INSERT INTO especialidades (cocinero_id,plato_id) VALUES (910002,910001);
  INSERT INTO preparaciones (cocinero_id,orden_id) VALUES (910002,992021);
  UPDATE ordenes SET estado=1 WHERE id=992021;
  UPDATE ordenes SET cantidad=2 WHERE id=992021;
END; $bloque$;$caso$);
SELECT pg_temp.probar('borrar orden solicitada sin preparaciones', 'ÉXITO',
$caso$DO $bloque$ BEGIN
  INSERT INTO reservaciones VALUES (911022,910001,2,0);
  INSERT INTO horarios VALUES (992022,910001,911022,'2026-11-11 10:00',INTERVAL '1 hour');
  INSERT INTO pedidos VALUES (992022,910001,910003);
  INSERT INTO ordenes (id,plato_id,pedido_id,cantidad,solicitado)
    VALUES (992022,910001,992022,1,'2026-11-11 10:30+00');
  DELETE FROM ordenes WHERE id=992022;
END; $bloque$;$caso$);
SELECT pg_temp.probar('no borrar orden preparada', 'RECHAZO',
$caso$DO $bloque$ BEGIN
  INSERT INTO reservaciones VALUES (911023,910001,2,0);
  INSERT INTO horarios VALUES (992023,910001,911023,'2026-11-11 10:00',INTERVAL '1 hour');
  INSERT INTO pedidos VALUES (992023,910001,910003);
  INSERT INTO ordenes (id,plato_id,pedido_id,cantidad,solicitado)
    VALUES (992023,910001,992023,1,'2026-11-11 10:30+00');
  INSERT INTO especialidades (cocinero_id,plato_id) VALUES (910002,910001);
  INSERT INTO preparaciones (cocinero_id,orden_id) VALUES (910002,992023);
  UPDATE ordenes SET estado=1 WHERE id=992023;
  DELETE FROM ordenes WHERE id=992023;
END; $bloque$;$caso$);

-- solo se crean reservaciones reservadas y los estados finales son inmutables.
SELECT pg_temp.probar('no insertar reservación cancelada', 'RECHAZO',
    $$INSERT INTO reservaciones (id,cliente_id,cantidad,estado) VALUES (911030,910001,2,3)$$);
SELECT pg_temp.probar('no agregar horario a liberada', 'RECHAZO',
$caso$DO $bloque$ BEGIN
  INSERT INTO reservaciones VALUES (911031,910001,2,0);
  INSERT INTO horarios VALUES (992031,910001,911031,'2026-11-11 10:00',INTERVAL '1 hour');
  UPDATE reservaciones SET estado=1 WHERE id=911031;
  UPDATE reservaciones SET estado=2 WHERE id=911031;
  INSERT INTO horarios VALUES (992032,910001,911031,'2026-11-12 10:00',INTERVAL '1 hour');
END; $bloque$;$caso$);
SELECT pg_temp.probar('no cambiar cantidad de reservación liberada', 'RECHAZO',
$caso$DO $bloque$ BEGIN
  INSERT INTO reservaciones VALUES (911032,910001,2,0);
  INSERT INTO horarios VALUES (992033,910001,911032,'2026-11-11 10:00',INTERVAL '1 hour');
  UPDATE reservaciones SET estado=1 WHERE id=911032;
  UPDATE reservaciones SET estado=2 WHERE id=911032;
  UPDATE reservaciones SET cantidad=3 WHERE id=911032;
END; $bloque$;$caso$);
SELECT pg_temp.probar('no cambiar horario final', 'RECHAZO',
$caso$DO $bloque$ BEGIN
  INSERT INTO reservaciones VALUES (911033,910001,2,0);
  INSERT INTO horarios VALUES (992034,910001,911033,'2026-11-11 10:00',INTERVAL '1 hour');
  UPDATE reservaciones SET estado=3 WHERE id=911033;
  UPDATE horarios SET duracion=INTERVAL '90 minutes' WHERE id=992034;
END; $bloque$;$caso$);
SELECT pg_temp.probar('no borrar horario de reservación cancelada', 'RECHAZO',
$caso$DO $bloque$ BEGIN
  INSERT INTO reservaciones VALUES (911034,910001,2,0);
  INSERT INTO horarios VALUES (992035,910001,911034,'2026-11-11 10:00',INTERVAL '1 hour');
  UPDATE reservaciones SET estado=3 WHERE id=911034;
  DELETE FROM horarios WHERE id=992035;
END; $bloque$;$caso$);

-- la cascada de especialidades no bloquea la baja; las FK protegen preparaciones.
SELECT pg_temp.probar('eliminar cocinero con especialidades se permite', 'ÉXITO',
$caso$DO $bloque$ DECLARE v_usuario INTEGER := 911201; BEGIN
  INSERT INTO usuarios (id,nombre) VALUES (v_usuario,'Cocinero eliminable');
  INSERT INTO actuaciones (rol_id,usuario_id) VALUES (910002,v_usuario);
  INSERT INTO especialidades (cocinero_id,plato_id) VALUES (v_usuario,910001);
  DELETE FROM usuarios WHERE id=v_usuario;
END; $bloque$;$caso$);
SELECT pg_temp.probar('preparaciones restringen eliminar cocinero', 'RECHAZO',
$caso$DO $bloque$ DECLARE v_usuario INTEGER := 911202; BEGIN
  INSERT INTO usuarios (id,nombre) VALUES (v_usuario,'Cocinero con preparación');
  INSERT INTO actuaciones (rol_id,usuario_id) VALUES (910002,v_usuario);
  INSERT INTO reservaciones VALUES (911202,910001,2,0);
  INSERT INTO horarios VALUES (992202,910001,911202,'2026-11-11 10:00',INTERVAL '1 hour');
  INSERT INTO pedidos VALUES (992202,910001,910003);
  INSERT INTO ordenes (id,plato_id,pedido_id,cantidad,solicitado)
    VALUES (992202,910001,992202,1,'2026-11-11 10:30+00');
  INSERT INTO especialidades (cocinero_id,plato_id) VALUES (v_usuario,910001);
  INSERT INTO preparaciones (cocinero_id,orden_id) VALUES (v_usuario,992202);
  DELETE FROM usuarios WHERE id=v_usuario;
END; $bloque$;$caso$);
SELECT pg_temp.probar('quitar rol directamente con especialidad se rechaza', 'RECHAZO',
$caso$DO $bloque$ DECLARE v_usuario INTEGER := 911203; BEGIN
  INSERT INTO usuarios (id,nombre) VALUES (v_usuario,'Cocinero con especialidad');
  INSERT INTO actuaciones (rol_id,usuario_id) VALUES (910002,v_usuario);
  INSERT INTO especialidades (cocinero_id,plato_id) VALUES (v_usuario,910001);
  DELETE FROM actuaciones WHERE usuario_id=v_usuario AND rol_id=910002;
END; $bloque$;$caso$);

-- capacidad asignada se calcula en cada instante distinto de la reservación.
SELECT pg_temp.probar('no sumar mesas de horarios en horas distintas', 'RECHAZO',
$caso$DO $bloque$ BEGIN
  INSERT INTO reservaciones VALUES (911040,910001,6,0);
  INSERT INTO horarios VALUES
    (992040,910001,911040,'2026-11-11 12:00',INTERVAL '1 hour'),
    (992041,910002,911040,'2026-11-11 20:00',INTERVAL '1 hour');
END; $bloque$;$caso$);
SELECT pg_temp.probar('sillas suficientes en cada horario distinto', 'ÉXITO',
$caso$DO $bloque$ BEGIN
  INSERT INTO reservaciones VALUES (911041,910001,4,0);
  INSERT INTO horarios VALUES
    (992042,910001,911041,'2026-11-11 12:00',INTERVAL '1 hour'),
    (992043,910002,911041,'2026-11-11 20:00',INTERVAL '1 hour');
END; $bloque$;$caso$);
SELECT pg_temp.probar('horarios propios cruzados en misma mesa se rechazan', 'RECHAZO',
$caso$DO $bloque$ BEGIN
  INSERT INTO reservaciones VALUES (911042,910001,2,0);
  INSERT INTO horarios VALUES (992044,910001,911042,'2026-11-11 10:00',INTERVAL '1 hour');
  INSERT INTO horarios VALUES (992045,910001,911042,'2026-11-11 11:00',INTERVAL '1 hour');
END; $bloque$;$caso$);

SELECT caso, esperado AS resultado_esperado, obtenido AS resultado_obtenido, estado
  FROM resultados_integridad
 ORDER BY caso;
SELECT COUNT(*) AS total_fallidos
  FROM resultados_integridad
 WHERE estado = 'FALLIDO';

ROLLBACK;
