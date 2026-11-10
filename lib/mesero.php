<?php

/*------------------------------------------------------------------*/
/**
 * @brief Busca la reservación activa que está ocupando una mesa en este momento.
 * @param resource $conn Conexión PostgreSQL activa.
 * @param int $mesa_id Mesa elegida por el mesero.
 * @return array|null Identificador y nombre del cliente, o null si no hay ninguna.
 * @pre La ocupación de una reservación dura dos horas desde su inicio.
 * @post El pedido se asocia al cliente que la mesa tiene ahora.
 */
function reservacion_vigente_de_mesa($conn, $mesa_id)
/*--------------------------------------------------------------------*/
{
    $reservaciones = consulta_filas(
        $conn,
        "SELECT r.cliente_id,
                u.nombre AS cliente
           FROM horarios h
           JOIN reservaciones r ON r.id = h.reservacion_id
           JOIN usuarios u ON u.id = r.cliente_id
          WHERE h.mesa_id = $1
            AND r.estado IN (0, 1)
            AND h.inicio <= LOCALTIMESTAMP
            AND h.inicio > LOCALTIMESTAMP - INTERVAL '2 hours'
          ORDER BY h.inicio DESC
          LIMIT 1",
        array($mesa_id)
    );
    return $reservaciones[0] ?? null;
}

/*------------------------------------------------------------------*/
/**
 * @brief Lee del formulario las cantidades pedidas de cada plato.
 * @return array Mapa de plato_id a cantidad, solo con cantidades mayores que cero.
 * @pre El formulario envía cantidad[plato_id] por cada plato del menú.
 * @post Los valores que no son enteros se descartan.
 */
function cantidades_por_plato()
/*--------------------------------------------------------------------*/
{
    $cantidades = $_POST['cantidad'] ?? array();
    if (!is_array($cantidades)) {
        return array();
    }

    $items = array();
    foreach ($cantidades as $plato_id => $texto_cantidad) {
        $cantidad = filter_var($texto_cantidad, FILTER_VALIDATE_INT);
        if ($cantidad !== false && $cantidad > 0) {
            $items[(int) $plato_id] = $cantidad;
        }
    }
    return $items;
}

/*------------------------------------------------------------------*/
/**
 * @brief Crea un pedido con sus órdenes para el cliente que ocupa una mesa.
 * @param resource $conn Conexión PostgreSQL activa.
 * @param int $mesa_id Mesa del pedido.
 * @param int $mesero_id Mesero de la sesión actual.
 * @param array $items Mapa de plato_id a cantidad.
 * @return object Resultado de en_transaccion; su resultado es el id del pedido.
 * @pre La mesa tiene una reservación vigente.
 * @post El pedido y todas sus órdenes se confirman juntos o no se aplican.
 */
function registrar_pedido($conn, $mesa_id, $mesero_id, $items)
/*--------------------------------------------------------------------*/
{
    return en_transaccion($conn, function () use ($conn, $mesa_id, $mesero_id, $items) {
        $reservacion = reservacion_vigente_de_mesa($conn, $mesa_id);
        if (!$reservacion) {
            throw new RuntimeException('No hay una reservación activa vigente para esta mesa.');
        }

        $pedido = ejecutar(
            $conn,
            'INSERT INTO pedidos (cliente_id, mesero_id)
             VALUES ($1, $2)
             RETURNING id',
            array((int) $reservacion['cliente_id'], $mesero_id)
        );
        $pedido_id = (int) $pedido->datos[0]['id'];

        foreach ($items as $plato_id => $cantidad) {
            ejecutar(
                $conn,
                'INSERT INTO ordenes (plato_id, pedido_id, cantidad)
                 VALUES ($1, $2, $3)',
                array($plato_id, $pedido_id, $cantidad)
            );
        }
        return $pedido_id;
    });
}

/*------------------------------------------------------------------*/
/**
 * @brief Consulta las órdenes de un pedido con su plato y estado.
 * @param resource $conn Conexión PostgreSQL activa.
 * @param int $pedido_id Pedido que se consulta.
 * @return array Órdenes con fecha y estado listos para mostrar.
 * @pre El pedido existe.
 * @post Las órdenes salen en el orden en que se solicitaron.
 */
function ordenes_de_pedido($conn, $pedido_id)
/*--------------------------------------------------------------------*/
{
    $ordenes = consulta_filas(
        $conn,
        'SELECT o.id AS orden_id,
                p.nombre AS plato,
                o.cantidad,
                o.solicitado,
                o.estado
           FROM ordenes o
           JOIN platos p ON p.id = o.plato_id
          WHERE o.pedido_id = $1
          ORDER BY o.solicitado, o.id',
        array($pedido_id)
    );
    return formatear_columnas($ordenes, array(
        'solicitado' => 'fecha_corta',
        'estado' => 'estado_orden'
    ));
}

/*------------------------------------------------------------------*/
/**
 * @brief Construye el formulario de pedido con el menú agrupado por categoría.
 * @param resource $conn Conexión PostgreSQL activa.
 * @param int $mesa_id Mesa del pedido.
 * @return string Formulario HTML con una cantidad por plato.
 * @pre Hay una reservación vigente en la mesa.
 * @post Permite agregar varios platos a un mismo pedido (PDF, sección 3.4).
 */
function formulario_pedido($conn, $mesa_id)
/*--------------------------------------------------------------------*/
{
    $platos = consulta_filas(
        $conn,
        'SELECT p.id,
                p.nombre,
                p.descripcion,
                p.precio,
                t.nombre AS tipo
           FROM platos p
           JOIN tipos t ON t.id = p.tipo_id
          ORDER BY t.id, p.nombre'
    );

    $html = "<form method='post' action='?opcion=realizar_pedidos&amp;mesa_id=".h($mesa_id)."'>";
    $tipo_actual = null;
    foreach ($platos as $plato) {
        if ($tipo_actual !== $plato['tipo']) {
            $html .= $tipo_actual === null ? '' : '</section>';
            $html .= "<section class='SECCION'><h2>".h($plato['tipo']).'</h2>';
            $tipo_actual = $plato['tipo'];
        }
        $html .= "<div class='PLATO'>"
               . "<span class='NOMBRE'>".h($plato['nombre']).'</span>'
               . "<span class='DESCRIPCION'>".h($plato['descripcion']).'</span>'
               . "<span class='PRECIO'>$".h($plato['precio']).'</span>'
               . "<label>Cantidad <input type='number' min='0' value='0'"
               . " name='cantidad[".(int) $plato['id']."]'></label>"
               . '</div>';
    }
    $html .= $tipo_actual === null ? '' : '</section>';
    return $html.'<button>Registrar pedido</button></form>';
}

/*------------------------------------------------------------------*/
/**
 * @brief Muestra y procesa el pedido de una mesa.
 * @param resource $conn Conexión PostgreSQL activa.
 * @return string Formulario de pedido, con las órdenes recién registradas.
 * @pre Se llama desde fn_realizar_pedidos, que ya incluye el botón del menú.
 * @post El pedido queda a nombre del mesero de la sesión, no de un dato del formulario.
 */
function pedido_mesa($conn)
/*--------------------------------------------------------------------*/
{
    $usuario = exigir_rol($conn, 'mesero');
    if (!$usuario) {
        return respuesta_sin_permiso('mesero');
    }

    $mesa_id = (int) ($_REQUEST['mesa_id'] ?? 0);
    $mensaje = '';
    $ordenes_registradas = '';
    if (es_envio_formulario()) {
        $items = cantidades_por_plato();
        if (!$items) {
            $mensaje = mostrar_error('Seleccione al menos un plato para crear el pedido.');
        } else {
            $operacion = registrar_pedido($conn, $mesa_id, $usuario['id'], $items);
            $mensaje = mensaje_operacion($operacion, 'Pedido registrado.');
            if ($operacion->exito) {
                $ordenes_registradas = '<h2>Pedido registrado</h2>'.html_tabla(
                    array(
                        'orden_id' => 'Orden',
                        'plato' => 'Plato',
                        'cantidad' => 'Cantidad',
                        'solicitado' => 'Solicitado',
                        'estado' => 'Estado'
                    ),
                    ordenes_de_pedido($conn, $operacion->resultado)
                );
            }
        }
    }

    $reservacion = reservacion_vigente_de_mesa($conn, $mesa_id);
    if (!$reservacion) {
        return $mensaje.mostrar_error('No hay una reservación activa vigente para esta mesa.');
    }
    return $mensaje
         . fn_mesero_avisos($conn)
         . '<h1>Pedido para mesa '.h($mesa_id).'</h1>'
         . '<p>Cliente: '.h($reservacion['cliente']).'</p>'
         . formulario_pedido($conn, $mesa_id)
         . $ordenes_registradas;
}

/*------------------------------------------------------------------*/
/**
 * @brief Avisa al mesero qué órdenes de sus pedidos ya están listas (PDF, secciones 3.5 y 4.1).
 * @param resource $conn Conexión PostgreSQL activa.
 * @return string Bloque de avisos que lib/programa.js actualiza cada 30 segundos.
 * @pre El usuario de la sesión tiene el rol mesero.
 * @post Solo aparecen órdenes de sus pedidos, con la mesa y un botón para entregarlas.
 */
function fn_mesero_avisos($conn)
/*--------------------------------------------------------------------*/
{
    $usuario = exigir_rol($conn, 'mesero');
    if (!$usuario) {
        return respuesta_sin_permiso('mesero');
    }

    $ordenes = consulta_filas(
        $conn,
        'SELECT o.id AS orden_id,
                o.pedido_id,
                mesa_de_pedido(o.pedido_id) AS mesa_id,
                p.nombre AS plato,
                o.cantidad,
                o.solicitado
           FROM pedidos pe
           JOIN ordenes o ON o.pedido_id = pe.id
           JOIN platos p ON p.id = o.plato_id
          WHERE pe.mesero_id = $1
            AND o.estado = 1
          ORDER BY o.solicitado, o.id',
        array($usuario['id'])
    );

    $botones = '';
    foreach ($ordenes as $orden) {
        $botones .= "<form method='post' action='?opcion=mesero_pedidos' class='form-inline'>"
                  . campo_oculto('orden_id', $orden['orden_id'])
                  . '<button>Entregar orden '.h($orden['orden_id']).'</button>'
                  . '</form>';
    }

    return "<div id='AVISOS' data-opcion='mesero_avisos'>"
         . '<h2>Órdenes listas para entregar</h2>'
         . html_tabla(
             array(
                 'orden_id' => 'Orden',
                 'pedido_id' => 'Pedido',
                 'mesa_id' => 'Mesa',
                 'plato' => 'Plato',
                 'cantidad' => 'Cantidad',
                 'solicitado' => 'Solicitado'
             ),
             formatear_columnas($ordenes, array('solicitado' => 'fecha_corta')),
             'No hay órdenes listas por ahora.'
         )
         . $botones
         . '</div>';
}

/*------------------------------------------------------------------*/
/**
 * @brief Registra la entrega de una orden lista (PDF, sección 3.5).
 * @param resource $conn Conexión PostgreSQL activa.
 * @param int $orden_id Orden entregada.
 * @param int $mesero_id Mesero de la sesión actual.
 * @return object Resultado de en_transaccion.
 * @pre La orden está lista y pertenece a un pedido de ese mesero.
 * @post La orden queda entregada, o nada cambia si no cumple lo anterior.
 */
function entregar_orden($conn, $orden_id, $mesero_id)
/*--------------------------------------------------------------------*/
{
    return en_transaccion($conn, function () use ($conn, $orden_id, $mesero_id) {
        ejecutar_en_fila(
            $conn,
            'UPDATE ordenes o
                SET estado = 2
              WHERE o.id = $1
                AND o.estado = 1
                AND EXISTS (
                    SELECT 1
                      FROM pedidos p
                     WHERE p.id = o.pedido_id
                       AND p.mesero_id = $2
                )
             RETURNING o.id',
            array($orden_id, $mesero_id),
            'La orden no está lista o no pertenece a sus pedidos.'
        );
    });
}

/*------------------------------------------------------------------*/
/**
 * @brief Muestra los pedidos activos del mesero y le permite entregar órdenes.
 * @param resource $conn Conexión PostgreSQL activa.
 * @return string Avisos y un bloque por pedido con sus órdenes.
 * @pre El usuario de la sesión tiene el rol mesero.
 * @post Solo se listan pedidos pendientes o de hoy.
 */
function fn_mesero_pedidos($conn)
/*--------------------------------------------------------------------*/
{
    $usuario = exigir_rol($conn, 'mesero');
    if (!$usuario) {
        return fn_boton_menu_principal().respuesta_sin_permiso('mesero');
    }

    $mensaje = '';
    if (es_envio_formulario()) {
        $orden_id = (int) ($_POST['orden_id'] ?? 0);
        $operacion = entregar_orden($conn, $orden_id, $usuario['id']);
        $mensaje = mensaje_operacion($operacion, 'Orden marcada como entregada.');
    }

    $pedidos = consulta_filas(
        $conn,
        'SELECT d.pedido_id,
                c.nombre AS cliente,
                d.mesa_id,
                d.primer_solicitado,
                d.estado
           FROM pedidos_detalle d
           JOIN usuarios c ON c.id = d.cliente_id
          WHERE d.mesero_id = $1
            AND (d.estado <> 2 OR d.primer_solicitado >= CURRENT_DATE)
          ORDER BY d.primer_solicitado DESC, d.pedido_id',
        array($usuario['id'])
    );

    $html = fn_boton_menu_principal().$mensaje.fn_mesero_avisos($conn).'<h1>Mis pedidos</h1>';
    if (!$pedidos) {
        $html .= '<p>No hay pedidos activos.</p>';
    }
    foreach ($pedidos as $pedido) {
        $html .= '<section class="registro">'
               . '<h2>Pedido '.h($pedido['pedido_id']).' · mesa '.h($pedido['mesa_id']).'</h2>'
               . '<p>Cliente: '.h($pedido['cliente'])
               . ' · '.h(fecha_corta($pedido['primer_solicitado']))
               . ' · '.h(estado_orden($pedido['estado'])).'</p>'
               . html_tabla(
                   array(
                       'orden_id' => 'Orden',
                       'plato' => 'Plato',
                       'cantidad' => 'Cantidad',
                       'solicitado' => 'Solicitado',
                       'estado' => 'Estado'
                   ),
                   ordenes_de_pedido($conn, (int) $pedido['pedido_id'])
               )
               . '</section>';
    }
    return $html;
}

?>
