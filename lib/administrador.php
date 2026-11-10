<?php

// Roles que gestiona el administrador según el PDF (sección 2 y sección 4.2).
const ROLES_GESTIONADOS = array('maitre', 'mesero', 'cocinero');

/*------------------------------------------------------------------*/
/**
 * @brief Agrega, modifica o elimina una mesa según el formulario enviado.
 * @param resource $conn Conexión PostgreSQL activa.
 * @return string Mensaje con el resultado de la operación.
 * @pre El usuario de la sesión tiene el rol administrador.
 * @post Una mesa con historial no se puede eliminar.
 */
function procesar_formulario_mesas($conn)
/*--------------------------------------------------------------------*/
{
    $accion = texto_recibido($_POST, 'accion');
    $mesa_id = (int) ($_POST['id'] ?? 0);
    $sillas = (int) ($_POST['sillas'] ?? 0);

    $operacion = en_transaccion($conn, function () use ($conn, $accion, $mesa_id, $sillas) {
        switch ($accion) {
            case 'agregar':
                ejecutar($conn, 'INSERT INTO mesas (sillas) VALUES ($1)', array($sillas));
                break;
            case 'modificar':
                ejecutar_en_fila(
                    $conn,
                    'UPDATE mesas
                        SET sillas = $1
                      WHERE id = $2
                     RETURNING id',
                    array($sillas, $mesa_id),
                    'La mesa ya no existe.'
                );
                break;
            case 'eliminar':
                ejecutar_en_fila(
                    $conn,
                    'DELETE FROM mesas
                      WHERE id = $1
                     RETURNING id',
                    array($mesa_id),
                    'La mesa ya no existe.'
                );
                break;
            default:
                throw new RuntimeException('La operación solicitada no es válida.');
        }
    });
    return mensaje_operacion($operacion, 'Operación realizada.');
}

/*------------------------------------------------------------------*/
/**
 * @brief Construye la tabla de mesas con sus acciones por fila.
 * @param array $mesas Filas con mesa_id y sillas.
 * @return string Tabla HTML.
 * @pre Ninguna.
 * @post Cada fila permite cambiar las sillas o eliminar esa mesa.
 */
function tabla_mesas($mesas)
/*--------------------------------------------------------------------*/
{
    $html = '<table><thead><tr>'
          . '<th>Mesa</th><th>Sillas</th><th>Cambiar sillas</th><th>Eliminar</th>'
          . '</tr></thead><tbody>';
    foreach ($mesas as $mesa) {
        $html .= '<tr>'
               . '<td>'.h($mesa['mesa_id']).'</td>'
               . '<td>'.h($mesa['sillas']).'</td>'
               . "<td><form method='post' class='form-inline'>"
               . campo_oculto('accion', 'modificar')
               . campo_oculto('id', $mesa['mesa_id'])
               . "<input type='number' min='1' name='sillas' value='".h($mesa['sillas'])."'"
               . " aria-label='Sillas de la mesa ".h($mesa['mesa_id'])."' required>"
               . '<button>Guardar</button>'
               . '</form></td>'
               . "<td><form method='post' class='form-inline'>"
               . campo_oculto('accion', 'eliminar')
               . campo_oculto('id', $mesa['mesa_id'])
               . '<button>Eliminar</button>'
               . '</form></td>'
               . '</tr>';
    }
    return $html.'</tbody></table>';
}

/*------------------------------------------------------------------*/
/**
 * @brief Gestiona las mesas y muestra el cupo total del restaurante (PDF, sección 3.1).
 * @param resource $conn Conexión PostgreSQL activa.
 * @return string Cupo total, tabla de mesas y formulario para agregar.
 * @pre El usuario de la sesión tiene el rol administrador.
 * @post El cupo total se calcula en la consulta sumando las sillas de todas las mesas.
 */
function fn_admin_mesas($conn)
/*--------------------------------------------------------------------*/
{
    if (!exigir_rol($conn, 'administrador')) {
        return fn_boton_menu_principal().respuesta_sin_permiso('administrador');
    }

    $mensaje = es_envio_formulario() ? procesar_formulario_mesas($conn) : '';
    $mesas = consulta_filas(
        $conn,
        'SELECT m.id AS mesa_id,
                m.sillas,
                SUM(m.sillas) OVER () AS sillas_totales
           FROM mesas m
          ORDER BY m.id'
    );
    $cupo_total = $mesas[0]['sillas_totales'] ?? 0;

    return fn_boton_menu_principal().$mensaje
         . '<h1>Mesas</h1>'
         . '<p>Cupo total: '.h($cupo_total).'</p>'
         . tabla_mesas($mesas)
         . '<h2>Agregar mesa</h2>'
         . "<form method='post'>"
         . campo_oculto('accion', 'agregar')
         . "<label>Sillas <input type='number' min='1' name='sillas' required></label>"
         . '<button>Agregar mesa</button>'
         . '</form>';
}

/*------------------------------------------------------------------*/
/**
 * @brief Agrega, modifica o elimina un plato según el formulario enviado.
 * @param resource $conn Conexión PostgreSQL activa.
 * @return string Mensaje con el resultado de la operación.
 * @pre El usuario de la sesión tiene el rol administrador.
 * @post Un plato ya pedido no se puede eliminar.
 */
function procesar_formulario_menu($conn)
/*--------------------------------------------------------------------*/
{
    $accion = texto_recibido($_POST, 'accion');
    $plato_id = (int) ($_POST['id'] ?? 0);
    $datos = array(
        trim(texto_recibido($_POST, 'nombre')),
        trim(texto_recibido($_POST, 'descripcion')),
        (int) ($_POST['tipo_id'] ?? 0),
        (int) ($_POST['tiempo'] ?? 0),
        texto_recibido($_POST, 'precio')
    );

    if ($accion !== 'eliminar' && ($datos[0] === '' || $datos[1] === '')) {
        return mostrar_error('Escriba el nombre y la descripción del plato.');
    }

    $operacion = en_transaccion($conn, function () use ($conn, $accion, $plato_id, $datos) {
        switch ($accion) {
            case 'agregar':
                ejecutar(
                    $conn,
                    'INSERT INTO platos (nombre, descripcion, tipo_id, tiempo, precio)
                     VALUES ($1, $2, $3, make_interval(mins => $4), $5)',
                    $datos
                );
                break;
            case 'modificar':
                ejecutar_en_fila(
                    $conn,
                    'UPDATE platos
                        SET nombre = $1,
                            descripcion = $2,
                            tipo_id = $3,
                            tiempo = make_interval(mins => $4),
                            precio = $5
                      WHERE id = $6
                     RETURNING id',
                    array_merge($datos, array($plato_id)),
                    'El plato ya no existe.'
                );
                break;
            case 'eliminar':
                ejecutar_en_fila(
                    $conn,
                    'DELETE FROM platos
                      WHERE id = $1
                     RETURNING id',
                    array($plato_id),
                    'El plato ya no existe.'
                );
                break;
            default:
                throw new RuntimeException('La operación solicitada no es válida.');
        }
    });
    return mensaje_operacion($operacion, 'Menú actualizado.');
}

/*------------------------------------------------------------------*/
/**
 * @brief Construye los campos del formulario de un plato.
 * @param array $tipos Categorías disponibles.
 * @param array|null $plato Plato que se modifica, o null para uno nuevo.
 * @return string Campos HTML con nombre, descripción, categoría, tiempo y precio.
 * @pre Ninguna.
 * @post Los valores no se interpretan como HTML.
 */
function formulario_plato($tipos, $plato)
/*--------------------------------------------------------------------*/
{
    return "<label>Nombre <input name='nombre' value='".h($plato['nombre'] ?? '')."' required>"
         . '</label>'
         . "<label>Descripción <textarea name='descripcion' required>"
         . h($plato['descripcion'] ?? '').'</textarea></label>'
         . "<label>Categoría <select name='tipo_id'>"
         . html_opciones($tipos, 'id', 'nombre', $plato['tipo_id'] ?? null)
         . '</select></label>'
         . "<label>Tiempo (minutos) <input type='number' min='1' name='tiempo'"
         . " value='".h($plato['minutos'] ?? 15)."' required></label>"
         . "<label>Precio <input type='number' min='0' step='0.01' name='precio'"
         . " value='".h($plato['precio'] ?? '')."' required></label>";
}

/*------------------------------------------------------------------*/
/**
 * @brief Gestiona el menú: agrega, modifica y elimina platos (PDF, sección 3.3).
 * @param resource $conn Conexión PostgreSQL activa.
 * @return string Tabla de platos, ordenada por categoría, y formularios.
 * @pre El usuario de la sesión tiene el rol administrador.
 * @post La tabla refleja los cambios recién aplicados.
 */
function fn_admin_menu($conn)
/*--------------------------------------------------------------------*/
{
    if (!exigir_rol($conn, 'administrador')) {
        return fn_boton_menu_principal().respuesta_sin_permiso('administrador');
    }

    $mensaje = es_envio_formulario() ? procesar_formulario_menu($conn) : '';
    $tipos = consulta_filas($conn, 'SELECT id, nombre FROM tipos ORDER BY id');
    $platos = consulta_filas(
        $conn,
        'SELECT p.id,
                p.nombre,
                p.descripcion,
                p.tipo_id,
                t.nombre AS categoria,
                (EXTRACT(EPOCH FROM p.tiempo) / 60)::INT AS minutos,
                p.precio
           FROM platos p
           JOIN tipos t ON t.id = p.tipo_id
          ORDER BY t.id, p.nombre'
    );

    $html = fn_boton_menu_principal().$mensaje
          . '<h1>Administrar menú</h1>'
          . html_tabla(
              array(
                  'id' => 'Id',
                  'nombre' => 'Plato',
                  'descripcion' => 'Descripción',
                  'categoria' => 'Categoría',
                  'minutos' => 'Tiempo (min)',
                  'precio' => 'Precio'
              ),
              $platos
          )
          . '<h2>Agregar plato</h2>'
          . "<form method='post'>"
          . campo_oculto('accion', 'agregar')
          . formulario_plato($tipos, null)
          . '<button>Agregar</button>'
          . '</form>'
          . '<h2>Modificar o eliminar plato</h2>';

    foreach ($platos as $plato) {
        $html .= '<details><summary>'.h($plato['nombre']).'</summary>'
               . "<form method='post'>"
               . campo_oculto('accion', 'modificar')
               . campo_oculto('id', $plato['id'])
               . formulario_plato($tipos, $plato)
               . '<button>Guardar cambios</button>'
               . '</form>'
               . "<form method='post'>"
               . campo_oculto('accion', 'eliminar')
               . campo_oculto('id', $plato['id'])
               . '<button>Eliminar</button>'
               . '</form></details>';
    }
    return $html;
}

/*------------------------------------------------------------------*/
/**
 * @brief Comprueba que un usuario sea un empleado gestionado por el administrador.
 * @param resource $conn Conexión PostgreSQL activa.
 * @param int $usuario_id Usuario que se quiere modificar o eliminar.
 * @return void
 * @pre Se llama dentro de en_transaccion.
 * @post Si es un cliente o no existe, lanza una excepción y nada cambia.
 */
function exigir_empleado($conn, $usuario_id)
/*--------------------------------------------------------------------*/
{
    $empleado = ejecutar(
        $conn,
        "SELECT a.usuario_id
           FROM actuaciones a
           JOIN roles r ON r.id = a.rol_id
          WHERE a.usuario_id = $1
            AND r.nombre IN ('maitre', 'mesero', 'cocinero')",
        array($usuario_id)
    );
    if ($empleado->cantidad === 0) {
        throw new RuntimeException('Seleccione un empleado válido.');
    }
}

/*------------------------------------------------------------------*/
/**
 * @brief Registra un empleado nuevo con su clave y su rol.
 * @param resource $conn Conexión PostgreSQL activa.
 * @param string $nombre Nombre del empleado.
 * @param string $clave Clave en texto; se guarda solo su hash.
 * @param string $rol Uno de ROLES_GESTIONADOS.
 * @return void
 * @pre Se llama dentro de en_transaccion.
 * @post Usuario y rol se confirman juntos.
 */
function registrar_empleado($conn, $nombre, $clave, $rol)
/*--------------------------------------------------------------------*/
{
    if ($clave === '') {
        throw new RuntimeException('La clave es obligatoria.');
    }
    if (!in_array($rol, ROLES_GESTIONADOS, true)) {
        throw new RuntimeException('Seleccione un rol de empleado válido.');
    }

    $usuario = ejecutar(
        $conn,
        "INSERT INTO usuarios (nombre, clave, fecha_clave)
         VALUES ($1, convert_to($2, 'UTF8'), now())
         RETURNING id",
        array($nombre, password_hash($clave, PASSWORD_DEFAULT))
    );
    ejecutar(
        $conn,
        'INSERT INTO actuaciones (usuario_id, rol_id)
         SELECT $1, id
           FROM roles
          WHERE nombre = $2',
        array((int) $usuario->datos[0]['id'], $rol)
    );
}

/*------------------------------------------------------------------*/
/**
 * @brief Cambia el nombre de un empleado y, si se escribió una, su clave.
 * @param resource $conn Conexión PostgreSQL activa.
 * @param int $empleado_id Empleado que se modifica.
 * @param string $nombre Nombre nuevo.
 * @param string $clave Clave nueva o texto vacío para conservar la actual.
 * @return void
 * @pre Se llama dentro de en_transaccion.
 * @post Un cliente nunca se modifica desde esta pantalla.
 */
function modificar_empleado($conn, $empleado_id, $nombre, $clave)
/*--------------------------------------------------------------------*/
{
    exigir_empleado($conn, $empleado_id);
    ejecutar(
        $conn,
        'UPDATE usuarios
            SET nombre = $1
          WHERE id = $2',
        array($nombre, $empleado_id)
    );
    if ($clave !== '') {
        ejecutar(
            $conn,
            "UPDATE usuarios
                SET clave = convert_to($1, 'UTF8'),
                    fecha_clave = now()
              WHERE id = $2",
            array(password_hash($clave, PASSWORD_DEFAULT), $empleado_id)
        );
    }
}

/*------------------------------------------------------------------*/
/**
 * @brief Procesa el registro, la modificación o la eliminación de un empleado.
 * @param resource $conn Conexión PostgreSQL activa.
 * @param int $administrador_id Usuario de la sesión actual.
 * @return string Mensaje con el resultado de la operación.
 * @pre El usuario de la sesión tiene el rol administrador.
 * @post El administrador no puede eliminar su propia cuenta.
 */
function procesar_formulario_empleados($conn, $administrador_id)
/*--------------------------------------------------------------------*/
{
    $accion = texto_recibido($_POST, 'accion');
    $empleado_id = (int) ($_POST['id'] ?? 0);
    $nombre = trim(texto_recibido($_POST, 'nombre'));
    $clave = texto_recibido($_POST, 'clave');
    $rol = texto_recibido($_POST, 'rol');

    if ($accion === 'eliminar' && $empleado_id === $administrador_id) {
        return mostrar_error('No puede eliminar su propia cuenta.');
    }

    $operacion = en_transaccion(
        $conn,
        function () use ($conn, $accion, $empleado_id, $nombre, $clave, $rol) {
            switch ($accion) {
                case 'agregar':
                    registrar_empleado($conn, $nombre, $clave, $rol);
                    break;
                case 'modificar':
                    modificar_empleado($conn, $empleado_id, $nombre, $clave);
                    break;
                case 'eliminar':
                    exigir_empleado($conn, $empleado_id);
                    ejecutar($conn, 'DELETE FROM usuarios WHERE id = $1', array($empleado_id));
                    break;
                default:
                    throw new RuntimeException('La operación solicitada no es válida.');
            }
        }
    );
    return mensaje_operacion($operacion, 'Empleados actualizados.');
}

/*------------------------------------------------------------------*/
/**
 * @brief Registra y gestiona maitres, meseros y cocineros (PDF, secciones 2 y 4.2).
 * @param resource $conn Conexión PostgreSQL activa.
 * @return string Tabla de empleados y formularios.
 * @pre El usuario de la sesión tiene el rol administrador.
 * @post Las claves nunca se muestran.
 */
function fn_admin_empleados($conn)
/*--------------------------------------------------------------------*/
{
    $usuario = exigir_rol($conn, 'administrador');
    if (!$usuario) {
        return fn_boton_menu_principal().respuesta_sin_permiso('administrador');
    }

    $mensaje = es_envio_formulario() ? procesar_formulario_empleados($conn, $usuario['id']) : '';
    $empleados = consulta_filas(
        $conn,
        "SELECT u.id,
                u.nombre,
                string_agg(r.nombre, ', ' ORDER BY r.nombre) AS roles
           FROM usuarios u
           JOIN actuaciones a ON a.usuario_id = u.id
           JOIN roles r ON r.id = a.rol_id
          WHERE r.nombre IN ('maitre', 'mesero', 'cocinero')
          GROUP BY u.id, u.nombre
          ORDER BY u.nombre"
    );

    $opciones_rol = '';
    foreach (ROLES_GESTIONADOS as $rol) {
        $opciones_rol .= '<option>'.h($rol).'</option>';
    }

    $html = fn_boton_menu_principal().$mensaje
          . '<h1>Empleados</h1>'
          . html_tabla(array('id' => 'Id', 'nombre' => 'Nombre', 'roles' => 'Roles'), $empleados)
          . '<h2>Registrar empleado</h2>'
          . "<form method='post'>"
          . campo_oculto('accion', 'agregar')
          . "<label>Nombre <input name='nombre' required></label>"
          . "<label>Clave <input type='password' name='clave' required></label>"
          . "<label>Rol <select name='rol'>".$opciones_rol.'</select></label>'
          . '<button>Registrar</button>'
          . '</form>'
          . '<h2>Modificar o eliminar empleado</h2>';

    foreach ($empleados as $empleado) {
        $html .= '<details><summary>'.h($empleado['nombre']).' ('.h($empleado['roles']).')'
               . '</summary>'
               . "<form method='post'>"
               . campo_oculto('accion', 'modificar')
               . campo_oculto('id', $empleado['id'])
               . "<label>Nombre <input name='nombre' value='".h($empleado['nombre'])."' required>"
               . '</label>'
               . "<label>Nueva clave (opcional) <input type='password' name='clave'></label>"
               . '<button>Guardar</button>'
               . '</form>'
               . "<form method='post'>"
               . campo_oculto('accion', 'eliminar')
               . campo_oculto('id', $empleado['id'])
               . '<button>Eliminar</button>'
               . '</form></details>';
    }
    return $html;
}

/*------------------------------------------------------------------*/
/**
 * @brief Deja las especialidades de un cocinero iguales a las casillas marcadas.
 * @param resource $conn Conexión PostgreSQL activa.
 * @param int $cocinero_id Cocinero elegido.
 * @param array $platos Identificadores de los platos marcados.
 * @return object Resultado de en_transaccion.
 * @pre Un trigger exige que el usuario tenga el rol de cocinero.
 * @post Solo se insertan y borran las diferencias con lo guardado.
 */
function guardar_especialidades($conn, $cocinero_id, $platos)
/*--------------------------------------------------------------------*/
{
    return en_transaccion($conn, function () use ($conn, $cocinero_id, $platos) {
        $actuales = ejecutar(
            $conn,
            'SELECT plato_id
               FROM especialidades
              WHERE cocinero_id = $1',
            array($cocinero_id)
        );
        $guardados = array_map('intval', array_column($actuales->datos, 'plato_id'));

        foreach (array_diff($guardados, $platos) as $plato_id) {
            ejecutar(
                $conn,
                'DELETE FROM especialidades
                  WHERE cocinero_id = $1
                    AND plato_id = $2',
                array($cocinero_id, $plato_id)
            );
        }
        foreach (array_diff($platos, $guardados) as $plato_id) {
            ejecutar(
                $conn,
                'INSERT INTO especialidades (cocinero_id, plato_id)
                 VALUES ($1, $2)',
                array($cocinero_id, $plato_id)
            );
        }
    });
}

/*------------------------------------------------------------------*/
/**
 * @brief Asigna a cada cocinero los platos que sabe preparar (PDF, sección 2).
 * @param resource $conn Conexión PostgreSQL activa.
 * @return string Selector de cocinero y casillas de platos.
 * @pre El usuario de la sesión tiene el rol administrador.
 * @post Tras guardar, sigue seleccionado el mismo cocinero.
 */
function fn_admin_especialidades($conn)
/*--------------------------------------------------------------------*/
{
    if (!exigir_rol($conn, 'administrador')) {
        return fn_boton_menu_principal().respuesta_sin_permiso('administrador');
    }

    $cocineros = consulta_filas(
        $conn,
        "SELECT u.id,
                u.nombre
           FROM usuarios u
           JOIN actuaciones a ON a.usuario_id = u.id
           JOIN roles r ON r.id = a.rol_id
          WHERE r.nombre = 'cocinero'
          ORDER BY u.nombre"
    );
    $cocinero_id = (int) ($_REQUEST['cocinero_id'] ?? ($cocineros[0]['id'] ?? 0));

    $mensaje = '';
    if (es_envio_formulario()) {
        $operacion = guardar_especialidades($conn, $cocinero_id, enteros_marcados('plato_id'));
        $mensaje = mensaje_operacion($operacion, 'Especialidades guardadas.');
    }

    $platos = consulta_filas($conn, 'SELECT id, nombre FROM platos ORDER BY nombre');
    $asignados = consulta_filas(
        $conn,
        'SELECT plato_id
           FROM especialidades
          WHERE cocinero_id = $1',
        array($cocinero_id)
    );
    $platos_asignados = array_map('intval', array_column($asignados, 'plato_id'));

    $html = fn_boton_menu_principal().$mensaje
          . '<h1>Especialidades</h1>'
          . "<form method='get'>"
          . campo_oculto('opcion', 'admin_especialidades')
          . "<label>Cocinero <select name='cocinero_id'>"
          . html_opciones($cocineros, 'id', 'nombre', $cocinero_id)
          . '</select></label>'
          . '<button>Ver especialidades</button>'
          . '</form>'
          . "<form method='post'>"
          . campo_oculto('cocinero_id', $cocinero_id);
    foreach ($platos as $plato) {
        $marca = in_array((int) $plato['id'], $platos_asignados, true) ? ' checked' : '';
        $html .= "<label class='casilla'>"
               . "<input type='checkbox' name='plato_id[]' value='".h($plato['id'])."'$marca> "
               . h($plato['nombre'])
               . '</label>';
    }
    return $html.'<button>Guardar especialidades</button></form>';
}

/*------------------------------------------------------------------*/
/**
 * @brief Convierte el inicio de un periodo en un texto legible.
 * @param string $periodo Uno de day, week o month.
 * @param string $inicio Inicio del periodo devuelto por date_trunc.
 * @return string Por ejemplo 2026-11-05, Semana del 2026-11-02 o 2026-11.
 * @pre El inicio comienza con el formato YYYY-MM-DD.
 * @post Ninguno.
 */
function etiqueta_periodo($periodo, $inicio)
/*--------------------------------------------------------------------*/
{
    if ($periodo === 'month') {
        return substr($inicio, 0, 7);
    }
    if ($periodo === 'week') {
        return 'Semana del '.substr($inicio, 0, 10);
    }
    return substr($inicio, 0, 10);
}

/*------------------------------------------------------------------*/
/**
 * @brief Cambia el inicio de periodo de cada fila por su texto legible.
 * @param array $filas Filas con la columna inicio_periodo.
 * @param string $periodo Uno de day, week o month.
 * @return array Las mismas filas con la etiqueta en inicio_periodo.
 * @pre Ninguna.
 * @post Las demás columnas no cambian.
 */
function con_etiqueta_periodo($filas, $periodo)
/*--------------------------------------------------------------------*/
{
    foreach ($filas as $indice => $fila) {
        $filas[$indice]['inicio_periodo'] = etiqueta_periodo($periodo, $fila['inicio_periodo']);
    }
    return $filas;
}

/*------------------------------------------------------------------*/
/**
 * @brief Genera los reportes de reservaciones, platos más pedidos y ventas (PDF, sección 3.6).
 * @param resource $conn Conexión PostgreSQL activa.
 * @return string Filtros y las tres tablas de resultados.
 * @pre El usuario de la sesión tiene el rol administrador.
 * @post Las ventas usan el precio actual de los platos, según docs/decisiones.md.
 */
function fn_admin_reportes($conn)
/*--------------------------------------------------------------------*/
{
    if (!exigir_rol($conn, 'administrador')) {
        return fn_boton_menu_principal().respuesta_sin_permiso('administrador');
    }

    $nombres_periodo = array('day' => 'Día', 'week' => 'Semana', 'month' => 'Mes');
    $periodo = texto_recibido($_GET, 'periodo', 'day');
    $aviso = '';
    if (!isset($nombres_periodo[$periodo])) {
        $periodo = 'day';
        $aviso = mostrar_error('El periodo no es válido. Se muestra por día.');
    }

    $desde = texto_recibido($_GET, 'desde');
    if (!fecha_en_formato($desde, 'Y-m-d')) {
        $desde = date('Y-01-01');
    }
    $hasta = texto_recibido($_GET, 'hasta');
    if (!fecha_en_formato($hasta, 'Y-m-d')) {
        $hasta = date('Y-m-d', strtotime('+1 day'));
    }

    $reservaciones = consulta_filas(
        $conn,
        'WITH primeros_inicios AS (
             SELECT h.reservacion_id,
                    MIN(h.inicio) AS primer_inicio
               FROM horarios h
               JOIN reservaciones r ON r.id = h.reservacion_id
              WHERE r.estado <> 3
                AND h.inicio >= $2::DATE::TIMESTAMP
                AND h.inicio < $3::DATE::TIMESTAMP
              GROUP BY h.reservacion_id
         )
         SELECT date_trunc($1, primer_inicio) AS inicio_periodo,
                COUNT(*) AS reservaciones
           FROM primeros_inicios
          GROUP BY date_trunc($1, primer_inicio)
          ORDER BY inicio_periodo',
        array($periodo, $desde, $hasta)
    );
    $platos = consulta_filas(
        $conn,
        "SELECT p.nombre,
                SUM(o.cantidad) AS unidades_solicitadas
           FROM ordenes o
           JOIN platos p ON p.id = o.plato_id
          WHERE o.solicitado >= ($1::DATE::TIMESTAMP AT TIME ZONE 'America/Bogota')
            AND o.solicitado < ($2::DATE::TIMESTAMP AT TIME ZONE 'America/Bogota')
          GROUP BY p.id, p.nombre
          ORDER BY unidades_solicitadas DESC, p.nombre",
        array($desde, $hasta)
    );
    $ventas = consulta_filas(
        $conn,
        "SELECT date_trunc($1, o.solicitado AT TIME ZONE 'America/Bogota') AS inicio_periodo,
                SUM(o.cantidad * p.precio) AS ventas
           FROM ordenes o
           JOIN platos p ON p.id = o.plato_id
          WHERE o.estado = 2
            AND o.solicitado >= ($2::DATE::TIMESTAMP AT TIME ZONE 'America/Bogota')
            AND o.solicitado < ($3::DATE::TIMESTAMP AT TIME ZONE 'America/Bogota')
          GROUP BY date_trunc($1, o.solicitado AT TIME ZONE 'America/Bogota')
          ORDER BY inicio_periodo",
        array($periodo, $desde, $hasta)
    );

    $opciones_periodo = '';
    foreach ($nombres_periodo as $valor => $nombre) {
        $marca = $valor === $periodo ? ' selected' : '';
        $opciones_periodo .= "<option value='$valor'$marca>$nombre</option>";
    }

    return fn_boton_menu_principal().$aviso
         . '<h1>Reportes</h1>'
         . "<form method='get'>"
         . campo_oculto('opcion', 'admin_reportes')
         . "<label>Periodo <select name='periodo'>".$opciones_periodo.'</select></label>'
         . "<label>Desde <input type='date' name='desde' value='".h($desde)."'></label>"
         . "<label>Hasta (sin incluir) <input type='date' name='hasta' value='".h($hasta)."'>"
         . '</label>'
         . '<button>Consultar</button>'
         . '</form>'
         . '<h2>Reservaciones por periodo</h2>'
         . html_tabla(
             array('inicio_periodo' => 'Periodo', 'reservaciones' => 'Reservaciones'),
             con_etiqueta_periodo($reservaciones, $periodo)
         )
         . '<h2>Platos más solicitados</h2>'
         . html_tabla(array('nombre' => 'Plato', 'unidades_solicitadas' => 'Unidades'), $platos)
         . '<h2>Ventas entregadas por periodo</h2>'
         . html_tabla(
             array('inicio_periodo' => 'Periodo', 'ventas' => 'Ventas'),
             con_etiqueta_periodo($ventas, $periodo)
         );
}

/*------------------------------------------------------------------*/
/**
 * @brief Muestra el historial de reservaciones y pedidos de un cliente (PDF, sección 4.3).
 * @param resource $conn Conexión PostgreSQL activa.
 * @return string Selector de cliente y dos tablas, las más recientes primero.
 * @pre El usuario de la sesión tiene el rol administrador.
 * @post No modifica datos.
 */
function fn_admin_historial($conn)
/*--------------------------------------------------------------------*/
{
    if (!exigir_rol($conn, 'administrador')) {
        return fn_boton_menu_principal().respuesta_sin_permiso('administrador');
    }

    $clientes = clientes_registrados($conn);
    $cliente_id = (int) ($_GET['cliente_id'] ?? ($clientes[0]['id'] ?? 0));

    $reservaciones = consulta_filas(
        $conn,
        "SELECT r.id AS reservacion_id,
                r.cantidad,
                r.estado,
                string_agg(h.mesa_id::TEXT, ', ' ORDER BY h.mesa_id) AS mesas,
                MIN(h.inicio) AS primer_inicio
           FROM reservaciones r
           LEFT JOIN horarios h ON h.reservacion_id = r.id
          WHERE r.cliente_id = $1
          GROUP BY r.id, r.cantidad, r.estado
          ORDER BY primer_inicio DESC NULLS LAST, r.id DESC",
        array($cliente_id)
    );
    $pedidos = consulta_filas(
        $conn,
        'SELECT d.pedido_id,
                d.mesa_id,
                d.primer_solicitado,
                d.estado AS estado_pedido,
                p.nombre AS plato,
                o.cantidad,
                o.estado AS estado_orden
           FROM pedidos_detalle d
           JOIN ordenes o ON o.pedido_id = d.pedido_id
           JOIN platos p ON p.id = o.plato_id
          WHERE d.cliente_id = $1
          ORDER BY d.primer_solicitado DESC, o.solicitado, o.id',
        array($cliente_id)
    );

    return fn_boton_menu_principal()
         . '<h1>Historial del cliente</h1>'
         . "<form method='get'>"
         . campo_oculto('opcion', 'admin_historial')
         . "<label>Cliente <select name='cliente_id'>"
         . html_opciones($clientes, 'id', 'nombre', $cliente_id)
         . '</select></label>'
         . '<button>Ver historial</button>'
         . '</form>'
         . '<h2>Reservaciones</h2>'
         . html_tabla(
             array(
                 'reservacion_id' => 'Reservación',
                 'cantidad' => 'Personas',
                 'estado' => 'Estado',
                 'mesas' => 'Mesas',
                 'primer_inicio' => 'Inicio'
             ),
             formatear_columnas($reservaciones, array(
                 'estado' => 'estado_reservacion',
                 'primer_inicio' => 'fecha_corta'
             ))
         )
         . '<h2>Pedidos y órdenes</h2>'
         . html_tabla(
             array(
                 'pedido_id' => 'Pedido',
                 'mesa_id' => 'Mesa',
                 'primer_solicitado' => 'Solicitado',
                 'estado_pedido' => 'Estado del pedido',
                 'plato' => 'Plato',
                 'cantidad' => 'Cantidad',
                 'estado_orden' => 'Estado de la orden'
             ),
             formatear_columnas($pedidos, array(
                 'primer_solicitado' => 'fecha_corta',
                 'estado_pedido' => 'estado_orden',
                 'estado_orden' => 'estado_orden'
             ))
         );
}

?>
