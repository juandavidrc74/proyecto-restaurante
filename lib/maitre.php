<?php

/*------------------------------------------------------------------*/
/**
 * @brief Construye el aviso de reservaciones próximas a comenzar (PDF, sección 4.1).
 * @param resource $conn Conexión PostgreSQL activa.
 * @return string Bloque de avisos que lib/programa.js actualiza cada 30 segundos.
 * @pre El plazo está en $minutos_aviso_reservacion, en etc/parametros.php.
 * @post Solo aparecen reservaciones que siguen en estado reservada.
 */
function aviso_reservaciones_html($conn)
/*--------------------------------------------------------------------*/
{
    global $minutos_aviso_reservacion;

    $reservaciones = consulta_filas(
        $conn,
        "SELECT r.id AS reservacion_id,
                u.nombre AS cliente,
                r.cantidad,
                string_agg(h.mesa_id::TEXT, ', ' ORDER BY h.mesa_id) AS mesas,
                MIN(h.inicio) AS inicio
           FROM reservaciones r
           JOIN usuarios u ON u.id = r.cliente_id
           JOIN horarios h ON h.reservacion_id = r.id
          WHERE r.estado = 0
            AND h.inicio >= LOCALTIMESTAMP
            AND h.inicio < LOCALTIMESTAMP + make_interval(mins => $1)
          GROUP BY r.id, u.nombre, r.cantidad
          ORDER BY inicio, r.id",
        array((int) $minutos_aviso_reservacion)
    );
    return "<div id='AVISOS' data-opcion='maitre_avisos'>"
         . '<h2>Avisos de próximas reservaciones</h2>'
         . html_tabla(
             array(
                 'reservacion_id' => 'Reservación',
                 'cliente' => 'Cliente',
                 'cantidad' => 'Personas',
                 'mesas' => 'Mesas',
                 'inicio' => 'Inicio'
             ),
             formatear_columnas($reservaciones, array('inicio' => 'fecha_corta')),
             'No hay reservaciones próximas a comenzar.'
         )
         . '</div>';
}

/*------------------------------------------------------------------*/
/**
 * @brief Entrega el aviso de reservaciones próximas para actualizar la página.
 * @param resource $conn Conexión PostgreSQL activa.
 * @return string Bloque de avisos.
 * @pre El usuario de la sesión tiene el rol maitre.
 * @post No modifica datos.
 */
function fn_maitre_avisos($conn)
/*--------------------------------------------------------------------*/
{
    if (!exigir_rol($conn, 'maitre')) {
        return respuesta_sin_permiso('maitre');
    }
    return aviso_reservaciones_html($conn);
}

/*------------------------------------------------------------------*/
/**
 * @brief Consulta las reservaciones que tienen un horario en un día.
 * @param resource $conn Conexión PostgreSQL activa.
 * @param string $dia Día en formato YYYY-MM-DD.
 * @return array Reservaciones con cliente, cantidad, estado, mesas e inicio.
 * @pre El día tiene un formato válido.
 * @post Cada reservación aparece una sola vez aunque tenga varias mesas.
 */
function reservaciones_del_dia($conn, $dia)
/*--------------------------------------------------------------------*/
{
    return consulta_filas(
        $conn,
        "SELECT r.id AS reservacion_id,
                u.nombre AS cliente,
                r.cantidad,
                r.estado,
                string_agg(h.mesa_id::TEXT, ', ' ORDER BY h.mesa_id) AS mesas,
                MIN(h.inicio) AS inicio
           FROM reservaciones r
           JOIN usuarios u ON u.id = r.cliente_id
           JOIN horarios h ON h.reservacion_id = r.id
          WHERE h.inicio >= $1::DATE::TIMESTAMP
            AND h.inicio < ($1::DATE + 1)::TIMESTAMP
          GROUP BY r.id, u.nombre, r.cantidad, r.estado
          ORDER BY inicio, r.id",
        array($dia)
    );
}

/*------------------------------------------------------------------*/
/**
 * @brief Cambia el estado de una reservación según la acción del maitre.
 * @param resource $conn Conexión PostgreSQL activa.
 * @param int $reservacion_id Reservación elegida.
 * @param string $accion Una de ocupar, liberar o cancelar.
 * @return string Mensaje con el resultado.
 * @pre Las transiciones de estado las valida un trigger de la base.
 * @post El estado cambia solo si la transición está permitida.
 */
function cambiar_estado_reservacion($conn, $reservacion_id, $accion)
/*--------------------------------------------------------------------*/
{
    $estados = array('ocupar' => 1, 'liberar' => 2, 'cancelar' => 3);
    if (!isset($estados[$accion])) {
        return mostrar_error('La acción solicitada no es válida.');
    }

    $estado = $estados[$accion];
    $operacion = en_transaccion($conn, function () use ($conn, $reservacion_id, $estado) {
        ejecutar_en_fila(
            $conn,
            'UPDATE reservaciones
                SET estado = $1
              WHERE id = $2
             RETURNING id',
            array($estado, $reservacion_id),
            'La reservación ya no existe.'
        );
    });
    return mensaje_operacion($operacion, 'Estado de la reservación actualizado.');
}

/*------------------------------------------------------------------*/
/**
 * @brief Construye las acciones permitidas para una reservación según su estado.
 * @param array $reservacion Fila con reservacion_id y estado.
 * @return string Botones y enlace de modificar; vacío si el estado es final.
 * @pre Reservada pasa a ocupada o cancelada; ocupada pasa a liberada o cancelada.
 * @post Solo se ofrecen esas transiciones. La base rechaza cancelar si ya hay pedidos.
 */
function acciones_reservacion($reservacion)
/*--------------------------------------------------------------------*/
{
    $estado = (int) $reservacion['estado'];
    if ($estado !== 0 && $estado !== 1) {
        return '';
    }

    $id = h($reservacion['reservacion_id']);
    $boton_estado = $estado === 0
        ? "<button name='accion' value='ocupar'>Marcar ocupada</button>"
        : "<button name='accion' value='liberar'>Liberar</button>";

    return "<form method='post'>"
         . campo_oculto('reservacion_id', $reservacion['reservacion_id'])
         . $boton_estado
         . "<button name='accion' value='cancelar'>Cancelar</button>"
         . '</form>'
         . "<a href='?opcion=maitre_modificar&amp;reservacion_id=$id'>Modificar</a>";
}

/*------------------------------------------------------------------*/
/**
 * @brief Muestra las reservaciones de un día y permite cambiar su estado.
 * @param resource $conn Conexión PostgreSQL activa.
 * @return string Avisos, selector de día y una ficha por reservación.
 * @pre El usuario de la sesión tiene el rol maitre.
 * @post Por omisión muestra el día de hoy.
 */
function fn_maitre_reservaciones($conn)
/*--------------------------------------------------------------------*/
{
    if (!exigir_rol($conn, 'maitre')) {
        return fn_boton_menu_principal().respuesta_sin_permiso('maitre');
    }

    $mensaje = '';
    if (es_envio_formulario()) {
        $reservacion_id = (int) ($_POST['reservacion_id'] ?? 0);
        $accion = texto_recibido($_POST, 'accion');
        $mensaje = cambiar_estado_reservacion($conn, $reservacion_id, $accion);
    }

    $dia = texto_recibido($_GET, 'dia', date('Y-m-d'));
    if (!fecha_en_formato($dia, 'Y-m-d')) {
        $dia = date('Y-m-d');
    }

    $html = fn_boton_menu_principal().$mensaje.aviso_reservaciones_html($conn)
          . '<h1>Reservaciones</h1>'
          . "<form method='get'>"
          . campo_oculto('opcion', 'maitre_reservaciones')
          . "<label>Día <input type='date' name='dia' value='".h($dia)."'></label>"
          . '<button>Consultar</button>'
          . '</form>';

    $reservaciones = reservaciones_del_dia($conn, $dia);
    if (!$reservaciones) {
        $html .= '<p>No hay reservaciones para este día.</p>';
    }
    foreach ($reservaciones as $reservacion) {
        $html .= '<section class="registro"><p>'
               . 'Reservación '.h($reservacion['reservacion_id'])
               . ' · '.h($reservacion['cliente'])
               . ' · '.h($reservacion['cantidad']).' personas'
               . ' · '.h(estado_reservacion($reservacion['estado']))
               . ' · mesas '.h($reservacion['mesas'])
               . ' · '.h(fecha_corta($reservacion['inicio']))
               . '</p>'
               . acciones_reservacion($reservacion)
               . '</section>';
    }
    return $html;
}

/*------------------------------------------------------------------*/
/**
 * @brief Lee del formulario los datos de una reservación.
 * @return array Cantidad, inicio (YYYY-MM-DD HH:MM), duración en minutos y mesas.
 * @pre El formulario usa los campos de campos_reservacion.
 * @post Los valores quedan con su tipo; aún no están validados.
 */
function leer_formulario_reservacion()
/*--------------------------------------------------------------------*/
{
    return array(
        'cantidad' => (int) ($_POST['cantidad'] ?? 0),
        'inicio' => str_replace('T', ' ', texto_recibido($_POST, 'inicio')),
        'duracion' => (int) ($_POST['duracion'] ?? 0),
        'mesas' => enteros_marcados('mesa_id')
    );
}

/*------------------------------------------------------------------*/
/**
 * @brief Valida el formato de los datos de una reservación antes de ir a la base.
 * @param array $datos Datos devueltos por leer_formulario_reservacion.
 * @return string|null Mensaje de error, o null si los datos son válidos.
 * @pre Cruces, cupo y sillas los valida la base de datos.
 * @post La duración personalizable queda entre 1 y 119 minutos.
 */
function error_formulario_reservacion($datos)
/*--------------------------------------------------------------------*/
{
    if (!fecha_en_formato($datos['inicio'], 'Y-m-d H:i')) {
        return 'Ingrese una fecha y hora válidas.';
    }
    if ($datos['duracion'] < 1 || $datos['duracion'] > 119) {
        return 'La duración debe estar entre 1 y 119 minutos.';
    }
    if (!$datos['mesas']) {
        return 'Seleccione al menos una mesa.';
    }
    return null;
}

/*------------------------------------------------------------------*/
/**
 * @brief Inserta un horario por cada mesa indicada de una reservación.
 * @param resource $conn Conexión PostgreSQL activa.
 * @param int $reservacion_id Reservación a la que pertenecen los horarios.
 * @param array $mesas Mesas que se asignan.
 * @param array $datos Inicio y duración en minutos.
 * @return void
 * @pre Se llama dentro de en_transaccion.
 * @post PostgreSQL ubica cada horario en la partición que le corresponde por fecha.
 */
function insertar_horarios($conn, $reservacion_id, $mesas, $datos)
/*--------------------------------------------------------------------*/
{
    foreach ($mesas as $mesa_id) {
        ejecutar(
            $conn,
            'INSERT INTO horarios (mesa_id, reservacion_id, inicio, duracion)
             VALUES ($1, $2, $3::TIMESTAMP, make_interval(mins => $4))',
            array($mesa_id, $reservacion_id, $datos['inicio'], $datos['duracion'])
        );
    }
}

/*------------------------------------------------------------------*/
/**
 * @brief Crea una reservación y, si hace falta, registra a su cliente nuevo.
 * @param resource $conn Conexión PostgreSQL activa.
 * @param int $cliente_id Cliente existente; se ignora si hay un nombre nuevo.
 * @param string $cliente_nuevo Nombre del cliente nuevo o texto vacío.
 * @param array $datos Datos validados de la reservación.
 * @return object Resultado de en_transaccion.
 * @pre Hay un cliente existente o un nombre nuevo.
 * @post Cliente, reservación y horarios se confirman juntos o no se aplican.
 */
function crear_reservacion($conn, $cliente_id, $cliente_nuevo, $datos)
/*--------------------------------------------------------------------*/
{
    return en_transaccion($conn, function () use ($conn, $cliente_id, $cliente_nuevo, $datos) {
        if ($cliente_nuevo !== '') {
            $usuario = ejecutar(
                $conn,
                'INSERT INTO usuarios (nombre)
                 VALUES ($1)
                 RETURNING id',
                array($cliente_nuevo)
            );
            $cliente_id = (int) $usuario->datos[0]['id'];
            ejecutar(
                $conn,
                "INSERT INTO actuaciones (usuario_id, rol_id)
                 SELECT $1, id
                   FROM roles
                  WHERE nombre = 'cliente'",
                array($cliente_id)
            );
        }

        $reservacion = ejecutar(
            $conn,
            'INSERT INTO reservaciones (cliente_id, cantidad)
             VALUES ($1, $2)
             RETURNING id',
            array($cliente_id, $datos['cantidad'])
        );
        insertar_horarios($conn, (int) $reservacion->datos[0]['id'], $datos['mesas'], $datos);
    });
}

/*------------------------------------------------------------------*/
/**
 * @brief Construye los campos comunes de los formularios de reservación.
 * @param resource $conn Conexión PostgreSQL activa.
 * @param array $valores Cantidad, inicio, duración y mesas marcadas.
 * @return string Campos HTML, incluidas las casillas de todas las mesas.
 * @pre El inicio viene en formato YYYY-MM-DD HH:MM o YYYY-MM-DDTHH:MM.
 * @post Se puede asignar más de una mesa a una reservación.
 */
function campos_reservacion($conn, $valores)
/*--------------------------------------------------------------------*/
{
    $inicio = str_replace(' ', 'T', substr((string) $valores['inicio'], 0, 16));
    $html = "<label>Personas <input type='number' min='1' name='cantidad'"
          . " value='".h($valores['cantidad'])."' required></label>"
          . "<label>Fecha y hora <input type='datetime-local' name='inicio'"
          . " value='".h($inicio)."' required></label>"
          . "<label>Duración (minutos) <input type='number' min='1' max='119' name='duracion'"
          . " value='".h($valores['duracion'])."' required></label>"
          . '<fieldset><legend>Mesas</legend>';

    $mesas = consulta_filas($conn, 'SELECT id, sillas FROM mesas ORDER BY id');
    foreach ($mesas as $mesa) {
        $marca = in_array((int) $mesa['id'], $valores['mesas'], true) ? ' checked' : '';
        $html .= "<label class='casilla'>"
               . "<input type='checkbox' name='mesa_id[]' value='".h($mesa['id'])."'$marca>"
               . ' Mesa '.h($mesa['id']).' ('.h($mesa['sillas']).' sillas)'
               . '</label>';
    }
    return $html.'</fieldset>';
}

/*------------------------------------------------------------------*/
/**
 * @brief Registra una reservación asignando mesas y horario (PDF, sección 3.2).
 * @param resource $conn Conexión PostgreSQL activa.
 * @return string Avisos, resultado de la operación y formulario.
 * @pre El usuario de la sesión tiene el rol maitre.
 * @post Si falla, el formulario conserva lo escrito para poder corregirlo.
 */
function fn_maitre_nueva($conn)
/*--------------------------------------------------------------------*/
{
    if (!exigir_rol($conn, 'maitre')) {
        return fn_boton_menu_principal().respuesta_sin_permiso('maitre');
    }

    $mensaje = '';
    $cliente_id = 0;
    $cliente_nuevo = '';
    $valores = array(
        'cantidad' => '',
        'inicio' => texto_recibido($_GET, 'inicio', date('Y-m-d H:i')),
        'duracion' => 90,
        'mesas' => array()
    );

    if (es_envio_formulario()) {
        $cliente_id = (int) ($_POST['cliente_id'] ?? 0);
        $cliente_nuevo = trim(texto_recibido($_POST, 'cliente_nuevo'));
        $datos = leer_formulario_reservacion();
        $error = error_formulario_reservacion($datos);
        if ($error === null && $cliente_id === 0 && $cliente_nuevo === '') {
            $error = 'Seleccione un cliente o escriba el nombre de uno nuevo.';
        }

        $valores = $datos;
        if ($error !== null) {
            $mensaje = mostrar_error($error);
        } else {
            $operacion = crear_reservacion($conn, $cliente_id, $cliente_nuevo, $datos);
            $mensaje = mensaje_operacion($operacion, 'Reservación registrada.');
            if ($operacion->exito) {
                $dia = substr($datos['inicio'], 0, 10);
                $mensaje .= "<a href='?opcion=maitre_reservaciones&amp;dia=".h($dia)."'>"
                          . 'Ver las reservaciones de ese día</a>';
            }
        }
    }

    return fn_boton_menu_principal().$mensaje.aviso_reservaciones_html($conn)
         . '<h1>Nueva reservación</h1>'
         . "<form method='post'>"
         . "<label>Cliente existente <select name='cliente_id'>"
         . "<option value='0'>Seleccione si no crea uno nuevo</option>"
         . html_opciones(clientes_registrados($conn), 'id', 'nombre', $cliente_id)
         . '</select></label>'
         . "<label>O nombre de cliente nuevo <input name='cliente_nuevo'"
         . " value='".h($cliente_nuevo)."'></label>"
         . campos_reservacion($conn, $valores)
         . '<button>Crear reservación</button>'
         . '</form>';
}

/*------------------------------------------------------------------*/
/**
 * @brief Consulta las mesas libres y el cupo ocupado alrededor de un instante.
 * @param resource $conn Conexión PostgreSQL activa.
 * @param string $instante Instante en formato YYYY-MM-DD HH:MM.
 * @return array Filas de sql/06_consultas.sql; mesa_id es NULL si no hay mesas libres.
 * @pre Una reservación ocupa su mesa durante dos horas desde su inicio.
 * @post Una mesa es libre si no hay cruce en las dos horas antes ni en las dos después.
 */
function consultar_disponibilidad($conn, $instante)
/*--------------------------------------------------------------------*/
{
    return consulta_filas(
        $conn,
        "WITH momento AS (
             SELECT $1::TIMESTAMP AS inicio
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
          ORDER BY m.id",
        array($instante)
    );
}

/*------------------------------------------------------------------*/
/**
 * @brief Muestra qué mesas y cuánto cupo hay disponibles en un instante.
 * @param resource $conn Conexión PostgreSQL activa.
 * @return string Avisos, selector de instante, cupo y mesas libres.
 * @pre El usuario de la sesión tiene el rol maitre.
 * @post No modifica datos.
 */
function fn_maitre_disponibilidad($conn)
/*--------------------------------------------------------------------*/
{
    if (!exigir_rol($conn, 'maitre')) {
        return fn_boton_menu_principal().respuesta_sin_permiso('maitre');
    }

    $instante = str_replace('T', ' ', texto_recibido($_GET, 'instante', date('Y-m-d H:i')));
    $html = fn_boton_menu_principal().aviso_reservaciones_html($conn)
          . '<h1>Disponibilidad</h1>';

    if (!fecha_en_formato($instante, 'Y-m-d H:i')) {
        $html .= mostrar_error('Ingrese una fecha y hora válidas.');
        $instante = date('Y-m-d H:i');
    }
    $instante_formulario = str_replace(' ', 'T', $instante);

    $html .= "<form method='get'>"
           . campo_oculto('opcion', 'maitre_disponibilidad')
           . "<label>Instante <input type='datetime-local' name='instante'"
           . " value='".h($instante_formulario)."' required></label>"
           . '<button>Consultar</button>'
           . '</form>';

    $filas = consultar_disponibilidad($conn, $instante);
    if ($filas) {
        $html .= '<p>Cupo ocupado en las dos horas siguientes: '
               . h($filas[0]['sillas_ocupadas']).' de '.h($filas[0]['sillas_totales'])
               . '; libre: '.h($filas[0]['sillas_libres']).'</p>';
    }

    $mesas_libres = array_filter($filas, function ($fila) {
        return $fila['mesa_id'] !== null;
    });
    return $html
         . html_tabla(
             array('mesa_id' => 'Mesa libre', 'sillas' => 'Sillas'),
             $mesas_libres,
             'No hay mesas libres en este instante.'
         )
         . "<a href='?opcion=maitre_nueva&amp;inicio=".rawurlencode($instante_formulario)."'>"
         . 'Crear reservación para este instante</a>';
}

/*------------------------------------------------------------------*/
/**
 * @brief Aplica a una reservación activa los cambios del formulario.
 * @param resource $conn Conexión PostgreSQL activa.
 * @param int $reservacion_id Reservación que se modifica.
 * @param array $datos Datos validados del formulario.
 * @return object Resultado de en_transaccion.
 * @pre Los triggers validan cruces, cupo, sillas y pedidos asociados.
 * @post Con la misma hora solo cambian las mesas distintas. Si una regla falla, nada cambia.
 */
function modificar_reservacion($conn, $reservacion_id, $datos)
/*--------------------------------------------------------------------*/
{
    return en_transaccion($conn, function () use ($conn, $reservacion_id, $datos) {
        $actual = ejecutar(
            $conn,
            'SELECT h.mesa_id,
                    h.inicio
               FROM reservaciones r
               JOIN horarios h ON h.reservacion_id = r.id
              WHERE r.id = $1
                AND r.estado IN (0, 1)',
            array($reservacion_id)
        );
        if ($actual->cantidad === 0) {
            throw new RuntimeException('Solo se pueden modificar reservaciones activas.');
        }

        ejecutar(
            $conn,
            'UPDATE reservaciones
                SET cantidad = $1
              WHERE id = $2',
            array($datos['cantidad'], $reservacion_id)
        );

        $inicios_actuales = array();
        foreach ($actual->datos as $horario) {
            $inicios_actuales[substr($horario['inicio'], 0, 16)] = true;
        }

        // Si cambia la hora, se reemplazan todos los horarios.
        if (array_keys($inicios_actuales) !== array($datos['inicio'])) {
            ejecutar(
                $conn,
                'DELETE FROM horarios
                  WHERE reservacion_id = $1',
                array($reservacion_id)
            );
            insertar_horarios($conn, $reservacion_id, $datos['mesas'], $datos);
            return;
        }

        // Con la misma hora, solo se tocan las mesas que cambiaron.
        $mesas_actuales = array_map('intval', array_column($actual->datos, 'mesa_id'));
        foreach (array_diff($mesas_actuales, $datos['mesas']) as $mesa_id) {
            ejecutar(
                $conn,
                'DELETE FROM horarios
                  WHERE reservacion_id = $1
                    AND mesa_id = $2',
                array($reservacion_id, $mesa_id)
            );
        }
        ejecutar(
            $conn,
            'UPDATE horarios
                SET duracion = make_interval(mins => $1)
              WHERE reservacion_id = $2',
            array($datos['duracion'], $reservacion_id)
        );
        $mesas_nuevas = array_diff($datos['mesas'], $mesas_actuales);
        insertar_horarios($conn, $reservacion_id, $mesas_nuevas, $datos);
    });
}

/*------------------------------------------------------------------*/
/**
 * @brief Muestra y procesa la modificación de una reservación activa.
 * @param resource $conn Conexión PostgreSQL activa.
 * @return string Avisos, resultado de la operación y formulario con los datos actuales.
 * @pre El usuario de la sesión tiene el rol maitre.
 * @post El formulario refleja siempre lo que quedó guardado.
 */
function fn_maitre_modificar($conn)
/*--------------------------------------------------------------------*/
{
    if (!exigir_rol($conn, 'maitre')) {
        return fn_boton_menu_principal().respuesta_sin_permiso('maitre');
    }

    $reservacion_id = (int) ($_REQUEST['reservacion_id'] ?? 0);
    $mensaje = '';
    if (es_envio_formulario()) {
        $datos = leer_formulario_reservacion();
        $error = error_formulario_reservacion($datos);
        if ($error !== null) {
            $mensaje = mostrar_error($error);
        } else {
            $operacion = modificar_reservacion($conn, $reservacion_id, $datos);
            $mensaje = mensaje_operacion($operacion, 'Reservación modificada.');
        }
    }

    $horarios = consulta_filas(
        $conn,
        'SELECT r.cantidad,
                h.mesa_id,
                h.inicio,
                (EXTRACT(EPOCH FROM h.duracion) / 60)::INT AS minutos
           FROM reservaciones r
           JOIN horarios h ON h.reservacion_id = r.id
          WHERE r.id = $1
            AND r.estado IN (0, 1)
          ORDER BY h.inicio, h.mesa_id',
        array($reservacion_id)
    );
    if (!$horarios) {
        return fn_boton_menu_principal().$mensaje
             . mostrar_error('No se encontró una reservación activa.')
             . aviso_reservaciones_html($conn);
    }

    $valores = array(
        'cantidad' => $horarios[0]['cantidad'],
        'inicio' => $horarios[0]['inicio'],
        'duracion' => $horarios[0]['minutos'],
        'mesas' => array_map('intval', array_column($horarios, 'mesa_id'))
    );
    return fn_boton_menu_principal().$mensaje.aviso_reservaciones_html($conn)
         . '<h1>Modificar reservación '.h($reservacion_id).'</h1>'
         . "<form method='post'>"
         . campo_oculto('reservacion_id', $reservacion_id)
         . campos_reservacion($conn, $valores)
         . '<button>Guardar cambios</button>'
         . '</form>';
}

?>
