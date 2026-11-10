-- La misma llave advisory serializa escrituras de agenda y lecturas de cupo.
-- Constante documentada del proyecto: 2026110501 (agenda global).
-- Las funciones de validación son VOLATILE, aun las de solo lectura: así, en READ COMMITTED,
-- cada sentencia ve lo que otra sesión confirmó mientras esta esperaba el bloqueo.

CREATE FUNCTION tiene_rol(p_usuario_id INTEGER, p_rol TEXT)
RETURNS BOOLEAN
LANGUAGE SQL
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM actuaciones a
        JOIN roles r ON r.id = a.rol_id
        WHERE a.usuario_id = p_usuario_id
          AND r.nombre = p_rol
    );
$$;

-- Regla decisiones sección 8: revisar solamente los instantes que pueden cambiar el
-- cupo dentro de la ventana indicada, con límites que permiten poda e índices.
CREATE FUNCTION validar_cupo_ventana(p_desde TIMESTAMP, p_hasta TIMESTAMP)
RETURNS VOID
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    v_instante TIMESTAMP;
    v_demanda BIGINT;
    v_sillas BIGINT;
BEGIN
    SELECT COALESCE(SUM(m.sillas), 0) INTO v_sillas FROM mesas m;

    FOR v_instante IN
        SELECT p_desde
        UNION
        SELECT DISTINCT h.inicio
          FROM horarios h
          JOIN reservaciones r ON r.id = h.reservacion_id
         WHERE r.estado IN (0, 1)
           AND h.inicio >= p_desde
           AND h.inicio < p_hasta
    LOOP
        SELECT COALESCE(SUM(r.cantidad), 0)
          INTO v_demanda
          FROM reservaciones r
          JOIN (
              SELECT DISTINCT h.reservacion_id
                FROM horarios h
                JOIN reservaciones ra ON ra.id = h.reservacion_id
               WHERE ra.estado IN (0, 1)
                 AND h.inicio <= v_instante
                 AND h.inicio > v_instante - INTERVAL '2 hours'
          ) ocupantes ON ocupantes.reservacion_id = r.id
         WHERE r.estado IN (0, 1);

        IF v_demanda > v_sillas THEN
            RAISE EXCEPTION 'El cupo del restaurante se supera a las %; ajuste las reservaciones o las mesas.', v_instante;
        END IF;
    END LOOP;
END;
$$;

-- Regla decisiones sección 8: el cambio de sillas afecta toda la agenda, único caso que
-- requiere revisar globalmente todos los instantes activos.
CREATE FUNCTION validar_cupo_agenda()
RETURNS VOID
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    v_desde TIMESTAMP;
    v_hasta TIMESTAMP;
BEGIN
    PERFORM pg_advisory_xact_lock(2026110501::BIGINT);
    SELECT MIN(h.inicio), MAX(h.inicio) + INTERVAL '1 microsecond'
      INTO v_desde, v_hasta
      FROM horarios h
      JOIN reservaciones r ON r.id = h.reservacion_id
     WHERE r.estado IN (0, 1);
    IF v_desde IS NOT NULL THEN
        PERFORM validar_cupo_ventana(v_desde, v_hasta);
    END IF;
END;
$$;

-- Regla decisiones sección 8: para cada reservación activa, las mesas asignadas deben
-- aportar las sillas solicitadas. Se cuenta cada mesa asignada una sola vez.
CREATE FUNCTION validar_sillas_reservacion(p_reservacion_id INTEGER)
RETURNS VOID
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    v_cantidad INTEGER;
    v_sillas BIGINT;
    v_instante TIMESTAMP;
BEGIN
    SELECT cantidad INTO v_cantidad
      FROM reservaciones
     WHERE id = p_reservacion_id AND estado IN (0, 1);
    IF NOT FOUND THEN
        RETURN;
    END IF;

    FOR v_instante IN
        SELECT DISTINCT h.inicio
          FROM horarios h
         WHERE h.reservacion_id = p_reservacion_id
    LOOP
        SELECT COALESCE(SUM(m.sillas), 0)
          INTO v_sillas
          FROM mesas m
         WHERE m.id IN (
             SELECT DISTINCT h.mesa_id
               FROM horarios h
              WHERE h.reservacion_id = p_reservacion_id
                AND h.inicio <= v_instante
                AND h.inicio > v_instante - INTERVAL '2 hours'
         );
        IF v_sillas < v_cantidad THEN
            RAISE EXCEPTION 'La reservación % requiere % sillas a las %, pero sus mesas asignadas solo ofrecen %.',
                p_reservacion_id, v_cantidad, v_instante, v_sillas;
        END IF;
    END LOOP;
END;
$$;

-- Reglas decisiones sección 8: sin cruces en una mesa para reservaciones activas; la
-- ventana ocupada es siempre [inicio, inicio + 2 horas).
CREATE FUNCTION validar_cruce_horario(p_horario_id INTEGER, p_inicio TIMESTAMP)
RETURNS VOID
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    v_mesa INTEGER;
    v_activa BOOLEAN;
BEGIN
    SELECT h.mesa_id, r.estado IN (0, 1)
      INTO v_mesa, v_activa
      FROM horarios h
      JOIN reservaciones r ON r.id = h.reservacion_id
     WHERE h.id = p_horario_id AND h.inicio = p_inicio;
    IF NOT FOUND OR NOT v_activa THEN
        RETURN;
    END IF;

    IF EXISTS (
        SELECT 1
          FROM horarios h
          JOIN reservaciones r ON r.id = h.reservacion_id
         WHERE h.mesa_id = v_mesa
           AND (h.id <> p_horario_id OR h.inicio <> p_inicio)
           AND r.estado IN (0, 1)
           AND h.inicio < p_inicio + INTERVAL '2 hours'
           AND h.inicio > p_inicio - INTERVAL '2 hours'
    ) THEN
        RAISE EXCEPTION 'La mesa % ya tiene una reservación activa en ese horario.', v_mesa;
    END IF;
END;
$$;

-- Regla decisiones sección 4: mesa del cliente en su primer solicitado; entre varias,
-- devolver la menor, incluyendo reservaciones liberadas pero no canceladas.
CREATE FUNCTION mesa_de_pedido(p_pedido_id INTEGER)
RETURNS INTEGER
LANGUAGE SQL
STABLE
AS $$
    WITH pedido AS (
        SELECT p.id, p.cliente_id, MIN(o.solicitado)::TIMESTAMP AS primer_solicitado
          FROM pedidos p
          LEFT JOIN ordenes o ON o.pedido_id = p.id
         WHERE p.id = p_pedido_id
         GROUP BY p.id, p.cliente_id
    )
    SELECT h.mesa_id
      FROM pedido p
      JOIN reservaciones r ON r.cliente_id = p.cliente_id AND r.estado IN (0, 1, 2)
      JOIN horarios h ON h.reservacion_id = r.id
     WHERE h.inicio <= p.primer_solicitado
       AND h.inicio + INTERVAL '2 hours' > p.primer_solicitado
     ORDER BY h.mesa_id
     LIMIT 1;
$$;

-- Regla PDF §3.4 y decisiones secciones 4 y 13: un horario conserva pedidos si es la mesa
-- derivada de un pedido cuyas órdenes caen en su ventana. Las demás mesas se pueden quitar.
CREATE FUNCTION horario_tiene_pedidos(p_horario_id INTEGER, p_inicio TIMESTAMP)
RETURNS BOOLEAN
LANGUAGE SQL
VOLATILE
AS $$
    SELECT EXISTS (
        SELECT 1
          FROM horarios h
          JOIN reservaciones r ON r.id = h.reservacion_id
          JOIN pedidos p ON p.cliente_id = r.cliente_id
          JOIN ordenes o ON o.pedido_id = p.id
         WHERE h.id = p_horario_id
           AND h.inicio = p_inicio
           AND o.solicitado::TIMESTAMP >= h.inicio
           AND o.solicitado::TIMESTAMP < h.inicio + INTERVAL '2 hours'
           AND mesa_de_pedido(p.id) = h.mesa_id
    );
$$;

-- Reglas decisiones secciones 4, 8 y 13: proteger la relación pedido-mesa y bloquear horarios finales.
CREATE FUNCTION proteger_horario()
RETURNS TRIGGER
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        IF EXISTS (SELECT 1 FROM reservaciones WHERE id = NEW.reservacion_id AND estado IN (2, 3)) THEN
            RAISE EXCEPTION 'No se puede agregar un horario a una reservación liberada o cancelada.';
        END IF;
        RETURN NEW;
    END IF;

    IF EXISTS (SELECT 1 FROM reservaciones WHERE id = OLD.reservacion_id AND estado IN (2, 3))
       OR (TG_OP = 'UPDATE' AND EXISTS (
            SELECT 1 FROM reservaciones WHERE id = NEW.reservacion_id AND estado IN (2, 3)
       )) THEN
        RAISE EXCEPTION 'No se puede cambiar ni borrar el horario de una reservación liberada o cancelada.';
    END IF;

    IF TG_OP = 'DELETE' THEN
        IF horario_tiene_pedidos(OLD.id, OLD.inicio) THEN
            RAISE EXCEPTION 'No se puede quitar ni mover este horario: tiene pedidos asociados.';
        END IF;
        RETURN OLD;
    END IF;

    IF (NEW.inicio IS DISTINCT FROM OLD.inicio
        OR NEW.mesa_id IS DISTINCT FROM OLD.mesa_id
        OR NEW.reservacion_id IS DISTINCT FROM OLD.reservacion_id)
       AND horario_tiene_pedidos(OLD.id, OLD.inicio) THEN
        RAISE EXCEPTION 'No se puede cambiar inicio, mesa o reservación del horario: tiene pedidos asociados.';
    END IF;
    RETURN NEW;
END;
$$;

-- Regla decisiones sección 8: tomar el bloqueo global antes de escribir horarios.
CREATE FUNCTION bloquear_agenda_horario()
RETURNS TRIGGER
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    PERFORM pg_advisory_xact_lock(2026110501::BIGINT);
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;

-- Regla decisiones secciones 6 y 8: id único en toda la tabla, sin cruces y cupo en la ventana.
CREATE FUNCTION validar_horario_inmediato()
RETURNS TRIGGER
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    -- En un movimiento entre particiones, el AFTER DELETE de origen ocurre
    -- antes que este AFTER INSERT; por eso la comprobación global se hace aquí.
    IF EXISTS (
        SELECT 1 FROM horarios
         WHERE id = NEW.id AND inicio <> NEW.inicio
    ) THEN
        RAISE EXCEPTION 'El identificador de horario % ya está en uso.', NEW.id;
    END IF;
    PERFORM validar_cruce_horario(NEW.id, NEW.inicio);
    PERFORM validar_cupo_ventana(NEW.inicio, NEW.inicio + INTERVAL '2 hours');
    RETURN NULL;
END;
$$;

-- Regla decisiones sección 7: una reservación activa debe terminar la transacción
-- con al menos un horario y con sillas suficientes.
CREATE FUNCTION validar_reservacion_diferida()
RETURNS TRIGGER
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    v_id INTEGER;
BEGIN
    v_id := CASE WHEN TG_OP = 'DELETE' THEN OLD.reservacion_id ELSE NEW.reservacion_id END;
    IF TG_OP = 'UPDATE' AND OLD.reservacion_id IS DISTINCT FROM NEW.reservacion_id
       AND EXISTS (SELECT 1 FROM reservaciones WHERE id = OLD.reservacion_id AND estado IN (0, 1)) THEN
        IF NOT EXISTS (SELECT 1 FROM horarios WHERE reservacion_id = OLD.reservacion_id) THEN
            RAISE EXCEPTION 'La reservación activa % debe tener al menos un horario antes de confirmar.', OLD.reservacion_id;
        END IF;
        PERFORM validar_sillas_reservacion(OLD.reservacion_id);
    END IF;
    IF EXISTS (SELECT 1 FROM reservaciones WHERE id = v_id AND estado IN (0, 1)) THEN
        IF NOT EXISTS (SELECT 1 FROM horarios WHERE reservacion_id = v_id) THEN
            RAISE EXCEPTION 'La reservación activa % debe tener al menos un horario antes de confirmar.', v_id;
        END IF;
        PERFORM validar_sillas_reservacion(v_id);
    END IF;
    RETURN NULL;
END;
$$;

-- Regla decisiones sección 8: serializar escrituras con el bloqueo global documentado.
-- PostgreSQL ejecuta los triggers de un mismo momento en orden alfabético: por su nombre,
-- este corre antes que tr_horarios_proteger, que así lee con el bloqueo ya tomado.
CREATE TRIGGER tr_horarios_bloquear_agenda
    BEFORE INSERT OR UPDATE OR DELETE ON horarios
    FOR EACH ROW EXECUTE FUNCTION bloquear_agenda_horario();

-- Reglas decisiones secciones 4 y 8: horarios de pedidos o de reservaciones finales no se alteran.
CREATE TRIGGER tr_horarios_proteger
    BEFORE INSERT OR UPDATE OR DELETE ON horarios
    FOR EACH ROW EXECUTE FUNCTION proteger_horario();

-- Regla decisiones sección 8: cruces para INSERT/UPDATE; cupo solo en su ventana.
CREATE TRIGGER tr_horarios_validar_inmediato
    AFTER INSERT OR UPDATE ON horarios
    FOR EACH ROW EXECUTE FUNCTION validar_horario_inmediato();

-- PostgreSQL 13 propaga los constraint triggers del padre a sus particiones;
-- así también quedan cubiertas las particiones que se agreguen en el futuro.
-- Regla decisiones sección 7: validar al final toda reservación activa.
CREATE CONSTRAINT TRIGGER tr_horarios_reservacion_diferida
    AFTER INSERT OR UPDATE OR DELETE ON horarios
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
    EXECUTE FUNCTION validar_reservacion_diferida();

-- Reglas decisiones secciones 4 y 8: serializar agenda, proteger pedidos y cerrar
-- los estados finales de las reservaciones.
CREATE FUNCTION validar_cambio_reservacion()
RETURNS TRIGGER
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    PERFORM pg_advisory_xact_lock(2026110501::BIGINT);
    IF TG_OP = 'DELETE' THEN
        IF OLD.estado IN (2, 3) THEN
            RAISE EXCEPTION 'No se puede borrar una reservación liberada o cancelada.';
        END IF;
        RETURN OLD;
    END IF;
    IF TG_OP = 'INSERT' AND NEW.estado <> 0 THEN
        RAISE EXCEPTION 'Una reservación nueva debe iniciar en estado reservada (0).';
    END IF;
    IF TG_OP = 'UPDATE' AND OLD.estado IN (2, 3)
       AND ROW(NEW.cliente_id, NEW.cantidad, NEW.estado)
           IS DISTINCT FROM ROW(OLD.cliente_id, OLD.cantidad, OLD.estado) THEN
        RAISE EXCEPTION 'No se puede modificar una reservación liberada o cancelada.';
    END IF;
    IF TG_OP = 'UPDATE' AND NEW.estado IS DISTINCT FROM OLD.estado THEN
        IF NOT ((OLD.estado = 0 AND NEW.estado IN (1, 3))
             OR (OLD.estado = 1 AND NEW.estado IN (2, 3))) THEN
            RAISE EXCEPTION 'Transición de reservación no permitida: % a %.', OLD.estado, NEW.estado;
        END IF;
        IF NEW.estado = 3 AND EXISTS (
            SELECT 1 FROM horarios h
             WHERE h.reservacion_id = OLD.id
               AND horario_tiene_pedidos(h.id, h.inicio)
        ) THEN
            RAISE EXCEPTION 'No se puede cancelar la reservación: uno de sus horarios tiene pedidos asociados.';
        END IF;
    END IF;
    IF TG_OP = 'UPDATE' AND NEW.cliente_id IS DISTINCT FROM OLD.cliente_id
       AND EXISTS (
            SELECT 1 FROM horarios h
             WHERE h.reservacion_id = OLD.id
               AND horario_tiene_pedidos(h.id, h.inicio)
       ) THEN
        RAISE EXCEPTION 'No se puede cambiar el cliente: la reservación tiene horarios con pedidos asociados.';
    END IF;
    RETURN NEW;
END;
$$;
-- Reglas decisiones secciones 4 y 8: transiciones, cancelación con pedidos y estado final.
CREATE TRIGGER tr_reservaciones_validar
    BEFORE INSERT OR UPDATE OR DELETE ON reservaciones
    FOR EACH ROW EXECUTE FUNCTION validar_cambio_reservacion();

-- Regla decisiones sección 8: al cambiar sillas, volver a validar asignaciones y cupo.
CREATE FUNCTION validar_cambio_mesa()
RETURNS TRIGGER
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
    v_reservacion INTEGER;
BEGIN
    PERFORM pg_advisory_xact_lock(2026110501::BIGINT);
    FOR v_reservacion IN
        SELECT DISTINCT h.reservacion_id
          FROM horarios h
          JOIN reservaciones r ON r.id = h.reservacion_id
         WHERE h.mesa_id = NEW.id AND r.estado IN (0, 1)
    LOOP
        PERFORM validar_sillas_reservacion(v_reservacion);
    END LOOP;
    PERFORM validar_cupo_agenda();
    RETURN NEW;
END;
$$;
CREATE FUNCTION bloquear_cambio_mesa()
RETURNS TRIGGER
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    PERFORM pg_advisory_xact_lock(2026110501::BIGINT);
    RETURN NEW;
END;
$$;
-- Regla decisiones sección 8: bloquear antes de leer disponibilidad al cambiar sillas.
CREATE TRIGGER tr_mesas_bloquear_cambio_sillas
    BEFORE UPDATE OF sillas ON mesas
    FOR EACH ROW EXECUTE FUNCTION bloquear_cambio_mesa();
-- Regla decisiones sección 8: validar asignaciones y cupo usando el nuevo número de sillas.
CREATE TRIGGER tr_mesas_validar_sillas
    AFTER UPDATE OF sillas ON mesas
    FOR EACH ROW EXECUTE FUNCTION validar_cambio_mesa();

-- Regla decisiones sección 9: el cocinero debe tener el rol antes de registrar una especialidad.
CREATE FUNCTION comprobar_rol_especialidad()
RETURNS TRIGGER LANGUAGE plpgsql VOLATILE AS $$
BEGIN
    IF NOT tiene_rol(NEW.cocinero_id, 'cocinero') THEN
        RAISE EXCEPTION 'El usuario % debe tener el rol de cocinero para registrar especialidades.', NEW.cocinero_id;
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER tr_especialidades_rol
    BEFORE INSERT OR UPDATE ON especialidades
    FOR EACH ROW EXECUTE FUNCTION comprobar_rol_especialidad();

-- Regla decisiones sección 9: el mesero asociado al pedido debe tener el rol de mesero.
CREATE FUNCTION comprobar_rol_pedido()
RETURNS TRIGGER LANGUAGE plpgsql VOLATILE AS $$
BEGIN
    IF NOT tiene_rol(NEW.mesero_id, 'mesero') THEN
        RAISE EXCEPTION 'El usuario % debe tener el rol de mesero para registrar el pedido.', NEW.mesero_id;
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER tr_pedidos_rol_mesero
    BEFORE INSERT OR UPDATE ON pedidos
    FOR EACH ROW EXECUTE FUNCTION comprobar_rol_pedido();

-- Regla decisiones secciones 4 y 13: la identidad del cliente no cambia si el pedido tiene órdenes.
CREATE FUNCTION proteger_cliente_pedido()
RETURNS TRIGGER
LANGUAGE plpgsql
VOLATILE
AS $$
BEGIN
    PERFORM pg_advisory_xact_lock(2026110501::BIGINT);
    IF NEW.cliente_id IS DISTINCT FROM OLD.cliente_id
       AND EXISTS (SELECT 1 FROM ordenes WHERE pedido_id = OLD.id) THEN
        RAISE EXCEPTION 'No se puede cambiar el cliente del pedido porque ya tiene órdenes.';
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER tr_pedidos_proteger_cliente
    BEFORE UPDATE OF cliente_id ON pedidos
    FOR EACH ROW EXECUTE FUNCTION proteger_cliente_pedido();

-- Regla decisiones sección 9: preparación por cocinero con especialidad en el plato ordenado.
CREATE FUNCTION comprobar_preparacion()
RETURNS TRIGGER LANGUAGE plpgsql VOLATILE AS $$
DECLARE
    v_plato INTEGER;
    v_estado INTEGER;
BEGIN
    IF NOT tiene_rol(NEW.cocinero_id, 'cocinero') THEN
        RAISE EXCEPTION 'El usuario % debe tener el rol de cocinero para preparar una orden.', NEW.cocinero_id;
    END IF;
    SELECT o.plato_id, o.estado INTO v_plato, v_estado
      FROM ordenes o WHERE o.id = NEW.orden_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'La orden % no existe.', NEW.orden_id;
    END IF;
    IF TG_OP = 'INSERT' AND v_estado <> 0 THEN
        RAISE EXCEPTION 'Solo se puede agregar una preparación cuando la orden está solicitada.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM especialidades e
                    WHERE e.cocinero_id = NEW.cocinero_id AND e.plato_id = v_plato) THEN
        RAISE EXCEPTION 'El cocinero % no tiene especialidad para el plato %.', NEW.cocinero_id, v_plato;
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER tr_preparaciones_comprobar
    BEFORE INSERT OR UPDATE ON preparaciones
    FOR EACH ROW EXECUTE FUNCTION comprobar_preparacion();

-- Regla decisiones sección 9: no alterar ni borrar preparaciones de órdenes ya preparadas.
CREATE FUNCTION proteger_preparacion_finalizada()
RETURNS TRIGGER LANGUAGE plpgsql VOLATILE AS $$
DECLARE
    v_estado INTEGER;
BEGIN
    SELECT estado INTO v_estado FROM ordenes WHERE id = OLD.orden_id;
    IF v_estado IN (1, 2) THEN
        RAISE EXCEPTION 'No se puede cambiar ni borrar la preparación: la orden ya está preparada o entregada.';
    END IF;
    IF TG_OP = 'UPDATE' THEN
        SELECT estado INTO v_estado FROM ordenes WHERE id = NEW.orden_id;
        IF v_estado IN (1, 2) THEN
            RAISE EXCEPTION 'No se puede cambiar ni borrar la preparación: la orden ya está preparada o entregada.';
        END IF;
    END IF;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER tr_preparaciones_proteger_finalizadas
    BEFORE UPDATE OR DELETE ON preparaciones
    FOR EACH ROW EXECUTE FUNCTION proteger_preparacion_finalizada();

-- Regla decisiones secciones 9, 12 y 13: no retirar roles usados por historial.
CREATE FUNCTION proteger_rol_con_historial()
RETURNS TRIGGER LANGUAGE plpgsql VOLATILE AS $$
DECLARE
    v_usuario INTEGER := OLD.usuario_id;
    v_rol TEXT;
BEGIN
    SELECT nombre INTO v_rol FROM roles WHERE id = OLD.rol_id;
    -- En una cascada desde usuarios, la fila padre ya no es visible; dejan
    -- que actúen las FK que protegen pedidos y preparaciones.
    IF NOT EXISTS (SELECT 1 FROM usuarios WHERE id = OLD.usuario_id) THEN
        RETURN OLD;
    END IF;
    IF TG_OP = 'UPDATE' AND NEW.usuario_id = OLD.usuario_id AND NEW.rol_id = OLD.rol_id THEN
        RETURN NEW;
    END IF;
    IF v_rol = 'cocinero' AND (
        EXISTS (SELECT 1 FROM especialidades WHERE cocinero_id = v_usuario)
        OR EXISTS (SELECT 1 FROM preparaciones WHERE cocinero_id = v_usuario)
    ) THEN
        RAISE EXCEPTION 'No se puede quitar el rol de cocinero: el usuario tiene especialidades o preparaciones registradas.';
    END IF;
    IF v_rol = 'mesero' AND EXISTS (SELECT 1 FROM pedidos WHERE mesero_id = v_usuario) THEN
        RAISE EXCEPTION 'No se puede quitar el rol de mesero: el usuario tiene pedidos registrados.';
    END IF;
    IF TG_OP = 'DELETE' THEN
        RETURN OLD;
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER tr_actuaciones_proteger_historial
    BEFORE DELETE OR UPDATE ON actuaciones
    FOR EACH ROW EXECUTE FUNCTION proteger_rol_con_historial();

-- Reglas decisiones secciones 4, 8, 9 y 13: orden vigente, identidad estable,
-- edición limitada y bloqueo antes de leer disponibilidad.
CREATE FUNCTION validar_orden()
RETURNS TRIGGER LANGUAGE plpgsql VOLATILE AS $$
DECLARE
    v_cliente INTEGER;
BEGIN
    IF TG_OP = 'INSERT' THEN
        PERFORM pg_advisory_xact_lock(2026110501::BIGINT);
        IF NEW.estado <> 0 THEN
            RAISE EXCEPTION 'Una orden nueva debe iniciar en estado solicitado (0).';
        END IF;
        SELECT cliente_id INTO v_cliente FROM pedidos WHERE id = NEW.pedido_id;
        IF NOT EXISTS (
            SELECT 1
              FROM reservaciones r
              JOIN horarios h ON h.reservacion_id = r.id
             WHERE r.cliente_id = v_cliente AND r.estado IN (0, 1)
               AND h.inicio <= NEW.solicitado::TIMESTAMP
               AND h.inicio + INTERVAL '2 hours' > NEW.solicitado::TIMESTAMP
        ) THEN
            RAISE EXCEPTION 'El cliente del pedido no tiene una reservación vigente a la hora solicitada.';
        END IF;
        RETURN NEW;
    END IF;

    IF TG_OP = 'DELETE' THEN
        IF OLD.estado <> 0 OR EXISTS (SELECT 1 FROM preparaciones WHERE orden_id = OLD.id) THEN
            RAISE EXCEPTION 'Solo se puede borrar una orden solicitada y sin preparaciones.';
        END IF;
        RETURN OLD;
    END IF;

    IF NEW.solicitado IS DISTINCT FROM OLD.solicitado
       OR NEW.pedido_id IS DISTINCT FROM OLD.pedido_id THEN
        RAISE EXCEPTION 'No se puede cambiar la fecha solicitada ni el pedido de una orden.';
    END IF;

    IF (NEW.plato_id IS DISTINCT FROM OLD.plato_id
        OR NEW.cantidad IS DISTINCT FROM OLD.cantidad)
       AND (OLD.estado <> 0
            OR EXISTS (SELECT 1 FROM preparaciones WHERE orden_id = OLD.id)) THEN
        RAISE EXCEPTION 'Solo se puede cambiar el plato o la cantidad de una orden solicitada y sin preparaciones.';
    END IF;

    IF NEW.estado IS DISTINCT FROM OLD.estado THEN
        IF NOT ((OLD.estado = 0 AND NEW.estado = 1) OR (OLD.estado = 1 AND NEW.estado = 2)) THEN
            RAISE EXCEPTION 'Transición de orden no permitida: % a %.', OLD.estado, NEW.estado;
        END IF;
        IF OLD.estado = 0 AND NEW.estado = 1
           AND NOT EXISTS (SELECT 1 FROM preparaciones WHERE orden_id = OLD.id) THEN
            RAISE EXCEPTION 'La orden necesita al menos una preparación antes de marcarse preparada.';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;
CREATE TRIGGER tr_ordenes_validar
    BEFORE INSERT OR UPDATE OR DELETE ON ordenes
    FOR EACH ROW EXECUTE FUNCTION validar_orden();

-- Regla decisiones sección 8: después de guardar cantidad, revisar sillas y cupo con el
-- valor nuevo; también cubre la validación diferida de toda reservación activa.
CREATE FUNCTION validar_reservacion_activa_diferida()
RETURNS TRIGGER LANGUAGE plpgsql VOLATILE AS $$
DECLARE
    v_horario RECORD;
BEGIN
    IF EXISTS (SELECT 1 FROM reservaciones WHERE id = NEW.id AND estado IN (0, 1)) THEN
        IF NOT EXISTS (SELECT 1 FROM horarios WHERE reservacion_id = NEW.id) THEN
            RAISE EXCEPTION 'La reservación activa % debe tener al menos un horario antes de confirmar.', NEW.id;
        END IF;
        PERFORM validar_sillas_reservacion(NEW.id);
        IF TG_OP = 'UPDATE' AND NEW.cantidad > OLD.cantidad THEN
            FOR v_horario IN
                SELECT inicio FROM horarios WHERE reservacion_id = NEW.id
            LOOP
                PERFORM validar_cupo_ventana(
                    v_horario.inicio,
                    v_horario.inicio + INTERVAL '2 hours'
                );
            END LOOP;
        END IF;
    END IF;
    RETURN NULL;
END;
$$;
CREATE CONSTRAINT TRIGGER tr_reservaciones_activa_diferida
    AFTER INSERT OR UPDATE ON reservaciones
    DEFERRABLE INITIALLY DEFERRED FOR EACH ROW
    EXECUTE FUNCTION validar_reservacion_activa_diferida();

-- Regla decisiones sección 9: estado del pedido derivado de todas sus órdenes.
CREATE VIEW pedidos_detalle AS
SELECT p.id AS pedido_id,
       p.cliente_id,
       p.mesero_id,
       mesa_de_pedido(p.id) AS mesa_id,
       MIN(o.solicitado) AS primer_solicitado,
       CASE
           WHEN COUNT(o.id) > 0 AND BOOL_AND(o.estado = 2) THEN 2
           WHEN COUNT(o.id) > 0 AND BOOL_AND(o.estado IN (1, 2)) THEN 1
           ELSE 0
       END AS estado
  FROM pedidos p
  LEFT JOIN ordenes o ON o.pedido_id = p.id
 GROUP BY p.id, p.cliente_id, p.mesero_id;
