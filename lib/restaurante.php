<?php
/*------------------------------------------------------------------*/
/**
 * @brief Genera el código HTML de un botón para regresar al inicio.
 * @return string Cadena de texto con el botón HTML.
 * @pre Ninguna.
 * @post El botón redirige a la opción raíz mediante JavaScript.
 */
function fn_boton_menu_principal()
/*--------------------------------------------------------------------*/
{
    $scr_menu = "window.open('?opcion=', '_top');";
    $retorno = "<button onClick=\"$scr_menu\">Menu del programa</button>";
    return $retorno;
}

/*------------------------------------------------------------------*/
/**
 * @brief Despliega los botones principales y los accesos habilitados por rol.
 * @param resource $conexion_bd Recurso de conexión a la base de datos.
 * @return string Fragmento HTML con el menú de navegación.
 * @pre El sistema debe estar cargado y la conexión debe ser válida.
 * @post Permite navegar por la carta, pedidos y opciones del rol vigente.
 */
function fn_menu_opciones($conn)
/*--------------------------------------------------------------------*/
{
    $scr_menu = "window.open('?opcion=desplegar_menu', '_top');";
    $scr_pedido = "window.open('?opcion=realizar_pedidos', '_top');";
    $retorno = "<h1>Opciones del programa</h1>"
             . "<div class='MENU_OPCIONES'>"
             . "<button onClick=\"$scr_menu\">Desplegar Menu</button>"
             . "<button onClick=\"$scr_pedido\">Realizar Pedido</button>"
             . "</div>"
             ;

    $usuario = usuario_actual();
    $roles = $usuario ? roles_de_usuario($conn, $usuario['id']) : array();
    $accesos = array(
        'administrador' => array(
            'admin_mesas' => 'Mesas',
            'admin_menu' => 'Administrar menú',
            'admin_empleados' => 'Empleados',
            'admin_especialidades' => 'Especialidades',
            'admin_reportes' => 'Reportes',
            'admin_historial' => 'Historial'
        ),
        'maitre' => array(
            'maitre_reservaciones' => 'Reservaciones',
            'maitre_nueva' => 'Nueva reservación',
            'maitre_disponibilidad' => 'Disponibilidad'
        ),
        'mesero' => array('mesero_pedidos' => 'Pedidos'),
        'cocinero' => array('cocinero_ordenes' => 'Órdenes')
    );
    $retorno .= "<div class='MENU_OPCIONES'>";
    foreach ($accesos as $rol => $opciones) {
        if (in_array($rol, $roles, true)) {
            foreach ($opciones as $opcion => $etiqueta) {
                $script = "window.open('?opcion=".h($opcion)."', '_top');";
                $retorno .= "<button onClick=\"".h($script)."\">".h($etiqueta)."</button>";
            }
        }
    }
    $retorno .= "</div>";

    if ($usuario) {
        $retorno .= '<p>Sesión: '.h($usuario['nombre']).'</p>'
                  . "<form method='post' action='?opcion=cerrar_sesion'>"
                  . "<button type='submit'>Cerrar sesión</button></form>";
    } else {
        $script_sesion = "window.open('?opcion=iniciar_sesion', '_top');";
        $retorno .= "<button onClick=\"$script_sesion\">Iniciar sesión</button>";
    }
    return $retorno;
}

/*------------------------------------------------------------------*/
/**
 * @brief Consulta y visualiza la carta de platos agrupados por tipo.
 * @param resource $conexion_bd Recurso de conexión a la base de datos.
 * @return string Lista HTML (ul) con las secciones y platos del restaurante.
 * @pre Debe existir la tabla platos y tipos con datos íntegros.
 * @post Genera la visualización estructurada del menú.
 */
function fn_desplegar_menu($conn)
/*--------------------------------------------------------------------*/
{
    $sentencia = "
    SELECT platos.id
         , platos.nombre
         , tipos.nombre AS tipo
         , descripcion
         , precio 
    FROM platos
    LEFT JOIN tipos ON platos.tipo_id=tipos.id
        ORDER BY tipos.id, platos.nombre
        ;";
    $resultado = procesar_query($sentencia, $conn);
    $retorno = fn_boton_menu_principal()."<br />";
    $tipo = "<div class='SECCION'>";
    foreach ($resultado->datos AS $plato) {
    if ($tipo != $plato['tipo']) {
        $retorno.= "</div><div class='SECCION'><h2>".h($plato['tipo'])."</h2>";
        $tipo = $plato['tipo'];
    }
        $retorno.= "<div class='PLATO'>"
                 .     "<span class='NOMBRE'>".h($plato['nombre'])."</span>"
                 .     "<span class='DESCRIPCION'>".h($plato['descripcion'])."</span>"
                 .     "<span class='PRECIO'>$".h($plato['precio'])."</span>"
                 . "</div>";
    }
    $retorno .= "</div>";
    $retorno = "<ul>$retorno</ul>";
    return $retorno;
}

/*------------------------------------------------------------------*/
/**
 * @brief Gestiona el flujo de pedidos, listando mesas o procesando una específica.
 * @param resource $conexion_bd Recurso de conexión a la base de datos.
 * @return string HTML con el listado de mesas disponibles o el formulario de pedido.
 * @pre El parámetro mesa_id en $_REQUEST determina el flujo de la función.
 * @post Facilita la selección de mesa para iniciar un pedido.
 */
function fn_realizar_pedidos($conn)
/*--------------------------------------------------------------------*/
{
    $retorno = fn_boton_menu_principal()."<br />";

    if (isset($_REQUEST['mesa_id']))
        $accion = "pedido_mesa";
    else
        $accion = "listar_mesas";

    switch ($accion) {
    case 'listar_mesas':
        //----------------------------------------
        // Listado de mesas
        //----------------------------------------
        $sentencia = "
            SELECT MES.id
                 , MES.sillas
                 , HOR.inicio
                 , USR.nombre as nombre_usr
            FROM mesas AS MES
            LEFT JOIN horarios      AS HOR ON MES.id = HOR.mesa_id
            LEFT JOIN reservaciones AS RES ON RES.id = HOR.reservacion_id
            LEFT JOIN usuarios      AS USR ON USR.id = RES.cliente_id
            WHERE HOR.inicio <= LOCALTIMESTAMP
              AND HOR.inicio > LOCALTIMESTAMP - INTERVAL '2 hours'
              AND RES.estado IN (0, 1)
            ORDER BY MES.id
            ";
        $resultado = procesar_query($sentencia, $conn);

        $botones_mesas = "";
        foreach ($resultado->datos as $mesa) {
            $script = "window.open('?opcion=realizar_pedidos&mesa_id=".$mesa['id']."', '_top');";
            $botones_mesas.= "<button onClick=\"$script\">"
                           .$mesa['id']." - ".h($mesa['nombre_usr'])
                           .' - '.h(fecha_corta($mesa['inicio']))."</button>";
        }
        if ($botones_mesas == "")
            $botones_mesas = "<p>No hay mesas con una reservación vigente.</p>";
        $retorno .= "<div class='MENU_OPCIONES'>".$botones_mesas."</div>";
        break;
    case 'pedido_mesa':
        $retorno .= pedido_mesa($conn);
    }

    return $retorno;
}
//------------------------------------------------------------
?>
