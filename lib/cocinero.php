<?php

/*------------------------------------------------------------------*/
/**
 * @brief Registra que un cocinero terminó de preparar una orden.
 * @param resource $conn Conexión PostgreSQL activa.
 * @param int $orden_id Orden que quedó lista.
 * @param int $cocinero_id Cocinero de la sesión actual.
 * @return object Resultado de en_transaccion.
 * @pre La orden está solicitada y el cocinero tiene la especialidad del plato.
 * @post La preparación y el cambio de estado se confirman juntos o no se aplican.
 */
function preparar_orden($conn, $orden_id, $cocinero_id)
/*--------------------------------------------------------------------*/
{
    return en_transaccion($conn, function () use ($conn, $orden_id, $cocinero_id) {
        ejecutar(
            $conn,
            'INSERT INTO preparaciones (cocinero_id, orden_id)
             VALUES ($1, $2)',
            array($cocinero_id, $orden_id)
        );
        ejecutar_en_fila(
            $conn,
            'UPDATE ordenes
                SET estado = 1
              WHERE id = $1
                AND estado = 0
             RETURNING id',
            array($orden_id),
            'La orden ya no está pendiente.'
        );
    });
}

/*------------------------------------------------------------------*/
/**
 * @brief Muestra al cocinero sus órdenes pendientes y le permite marcarlas listas.
 * @param resource $conn Conexión PostgreSQL activa.
 * @return string Lista de órdenes, las más demoradas primero (PDF, sección 2).
 * @pre El usuario de la sesión tiene el rol cocinero.
 * @post Solo aparecen platos de las especialidades del cocinero.
 */
function fn_cocinero_ordenes($conn)
/*--------------------------------------------------------------------*/
{
    $usuario = exigir_rol($conn, 'cocinero');
    if (!$usuario) {
        return fn_boton_menu_principal().respuesta_sin_permiso('cocinero');
    }

    $mensaje = '';
    if (es_envio_formulario()) {
        $orden_id = (int) ($_POST['orden_id'] ?? 0);
        $operacion = preparar_orden($conn, $orden_id, $usuario['id']);
        $mensaje = mensaje_operacion($operacion, 'Orden marcada como lista.');
    }

    $ordenes = consulta_filas(
        $conn,
        'SELECT o.id AS orden_id,
                p.nombre AS plato,
                (EXTRACT(EPOCH FROM p.tiempo) / 60)::INT AS minutos,
                o.cantidad,
                o.solicitado
           FROM especialidades e
           JOIN platos p ON p.id = e.plato_id
           JOIN ordenes o ON o.plato_id = p.id AND o.estado = 0
          WHERE e.cocinero_id = $1
          ORDER BY p.tiempo DESC, o.solicitado, o.id',
        array($usuario['id'])
    );

    $html = fn_boton_menu_principal().$mensaje.'<h1>Órdenes pendientes</h1>';
    if (!$ordenes) {
        $html .= '<p>No hay órdenes pendientes.</p>';
    }
    foreach ($ordenes as $orden) {
        $html .= '<section class="registro"><p>'
               . 'Orden '.h($orden['orden_id'])
               . ' · '.h($orden['plato'])
               . ' · cantidad '.h($orden['cantidad'])
               . ' · preparación '.h($orden['minutos']).' min'
               . ' · solicitada '.h(fecha_corta($orden['solicitado']))
               . '</p>'
               . "<form method='post'>"
               . campo_oculto('orden_id', $orden['orden_id'])
               . '<button>Marcar listo</button>'
               . '</form></section>';
    }
    return $html;
}

?>
