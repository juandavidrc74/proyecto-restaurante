<?php

/*------------------------------------------------------------------*/
/**
 * @brief Obtiene la identidad almacenada en la sesión actual.
 * @return array|null Identificador y nombre del empleado autenticado.
 * @pre La sesión fue iniciada desde index.php.
 * @post Devuelve null si no existe una sesión autenticada.
 */
function usuario_actual()
/*--------------------------------------------------------------------*/
{
    if (empty($_SESSION['usuario_id'])) {
        return null;
    }
    return array(
        'id' => (int) $_SESSION['usuario_id'],
        'nombre' => (string) ($_SESSION['usuario_nombre'] ?? '')
    );
}

/*------------------------------------------------------------------*/
/**
 * @brief Consulta en la base los roles actuales de un usuario.
 * @param resource $conn Conexión PostgreSQL activa.
 * @param int $id Identificador del usuario.
 * @return array Nombres de los roles asignados.
 * @pre El usuario puede no existir o no tener roles.
 * @post La respuesta siempre es una lista de nombres de rol.
 */
function roles_de_usuario($conn, $id)
/*--------------------------------------------------------------------*/
{
    $consulta = consulta_parametrizada(
        'SELECT r.nombre
           FROM actuaciones a
           JOIN roles r ON r.id = a.rol_id
          WHERE a.usuario_id = $1
          ORDER BY r.nombre',
        array((int) $id),
        $conn
    );
    if ($consulta->error !== null) {
        return array();
    }
    return array_column($consulta->datos, 'nombre');
}

/*------------------------------------------------------------------*/
/**
 * @brief Comprueba desde la base que el empleado conserve un rol requerido.
 * @param resource $conn Conexión PostgreSQL activa.
 * @param string $rol Nombre del rol que se exige.
 * @return array|false Identidad autenticada con sus roles o false.
 * @pre El usuario inició sesión en esta sesión del navegador.
 * @post La autorización se valida de nuevo en cada petición.
 */
function exigir_rol($conn, $rol)
/*--------------------------------------------------------------------*/
{
    $usuario = usuario_actual();
    if ($usuario === null) {
        return false;
    }

    $consulta = consulta_parametrizada(
        'SELECT id, nombre
           FROM usuarios
          WHERE id = $1',
        array($usuario['id']),
        $conn
    );
    if ($consulta->error !== null || !$consulta->datos) {
        return false;
    }

    $fila_usuario = $consulta->datos[0];
    $roles = roles_de_usuario($conn, (int) $fila_usuario['id']);
    if (!in_array($rol, $roles, true)) {
        return false;
    }

    $_SESSION['usuario_nombre'] = $fila_usuario['nombre'];
    return array(
        'id' => (int) $fila_usuario['id'],
        'nombre' => $fila_usuario['nombre'],
        'roles' => $roles
    );
}

/*------------------------------------------------------------------*/
/**
 * @brief Genera la respuesta uniforme para una sesión sin el rol requerido.
 * @param string $rol Nombre del rol que exige la opción.
 * @return string Mensaje y enlace al formulario de inicio de sesión.
 * @pre Se llamó desde una opción protegida por rol.
 * @post No contiene información de la operación que quedó bloqueada.
 */
function respuesta_sin_permiso($rol)
/*--------------------------------------------------------------------*/
{
    return mostrar_error('Se requiere iniciar sesión como '.$rol.'.')
         . "<a href='?opcion=iniciar_sesion'>Iniciar sesión</a>";
}

/*------------------------------------------------------------------*/
/**
 * @brief Presenta el formulario y autentica a un empleado.
 * @param resource $conn Conexión PostgreSQL activa.
 * @return string Formulario de inicio o menú tras autenticarse.
 * @pre Solo se muestran usuarios con roles de empleado.
 * @post Al autenticar, renueva el identificador de sesión.
 */
function fn_iniciar_sesion($conn)
/*--------------------------------------------------------------------*/
{
    $mensaje = '';
    if (($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST') {
        $id_usuario = (int) ($_POST['usuario_id'] ?? 0);
        $clave = texto_recibido($_POST, 'clave');
        $sentencia = "SELECT u.id, u.nombre, u.clave
                        FROM usuarios u
                        JOIN actuaciones a ON a.usuario_id = u.id
                        JOIN roles r ON r.id = a.rol_id
                       WHERE u.id = $1
                         AND r.nombre IN ('administrador', 'maitre', 'mesero', 'cocinero')
                    GROUP BY u.id, u.nombre, u.clave";
        $resultado = consulta_parametrizada($sentencia, array($id_usuario), $conn);
        $fila_usuario = $resultado->datos[0] ?? null;
        $hash = $fila_usuario && $fila_usuario['clave'] !== null
            ? pg_unescape_bytea($fila_usuario['clave'])
            : '';

        if ($fila_usuario && password_verify($clave, $hash)) {
            session_regenerate_id(true);
            $_SESSION['usuario_id'] = (int) $fila_usuario['id'];
            $_SESSION['usuario_nombre'] = $fila_usuario['nombre'];
            return mostrar_exito('Sesión iniciada.').fn_menu_opciones($conn);
        }
        $mensaje = mostrar_error(
            'No fue posible iniciar sesión. Verifique el empleado y la clave.'
        );
    }

    $empleados = consulta_filas(
        $conn,
        "SELECT DISTINCT u.id, u.nombre
           FROM usuarios u
           JOIN actuaciones a ON a.usuario_id = u.id
           JOIN roles r ON r.id = a.rol_id
          WHERE r.nombre IN ('administrador', 'maitre', 'mesero', 'cocinero')
          ORDER BY u.nombre, u.id"
    );
    $html = fn_boton_menu_principal().$mensaje
          . '<h1>Iniciar sesión</h1>'
          . "<form method='post' action='?opcion=iniciar_sesion'>"
          . '<label>Empleado <select name="usuario_id" required>';
    foreach ($empleados as $empleado) {
        $html .= '<option value="'.h($empleado['id']).'">'
              . h($empleado['nombre']).'</option>';
    }
    return $html.'</select></label>'
         . '<label>Clave <input type="password" name="clave" required></label>'
         . '<button type="submit">Iniciar sesión</button></form>';
}

/*------------------------------------------------------------------*/
/**
 * @brief Cierra la sesión del empleado mediante una solicitud POST.
 * @param resource $conn Conexión PostgreSQL activa.
 * @return string Confirmación o aviso de que se requiere POST.
 * @pre La sesión fue iniciada desde index.php.
 * @post El identificador de sesión y su cookie quedan invalidados.
 */
function fn_cerrar_sesion($conn)
/*--------------------------------------------------------------------*/
{
    if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') {
        return fn_boton_menu_principal()
             . mostrar_error('Para cerrar la sesión, use el botón de cierre del menú.');
    }

    $_SESSION = array();
    if (ini_get('session.use_cookies')) {
        $parametros_cookie = session_get_cookie_params();
        setcookie(session_name(), '', array(
            'expires' => time() - 42000,
            'path' => $parametros_cookie['path'],
            'domain' => $parametros_cookie['domain'],
            'secure' => $parametros_cookie['secure'],
            'httponly' => $parametros_cookie['httponly'],
            'samesite' => 'Lax'
        ));
    }
    session_destroy();
    return fn_boton_menu_principal().mostrar_exito('Sesión cerrada.');
}

?>
