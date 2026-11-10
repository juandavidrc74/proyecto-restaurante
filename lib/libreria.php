<?php

/*------------------------------------------------------------------*/
/**
 * @brief Establece una conexión con una base de datos PostgreSQL.
 * @param string $anfitrion Dirección del servidor de base de datos (host).
 * @param string $nombre_bd Nombre de la base de datos.
 * @param string $usuario Nombre del usuario de la base de datos.
 * @param string $password Contraseña del usuario de la base de datos.
 * @return resource Recurso de la conexión establecida.
 * @pre El servicio de PostgreSQL debe estar activo y accesible.
 * @post Si la conexión falla, el script termina su ejecución.
 */
function pg_conectar($host, $dbname, $user, $password)
/*--------------------------------------------------------------------*/
{
    $conn = pg_connect("host=$host dbname=$dbname user=$user password=$password");
    if (!$conn)
        die("Error de conexión: ");//.pg_last_error());

    return $conn;
}

/*------------------------------------------------------------------*/
/**
 * @brief Formatea una variable para su visualización en depuración.
 * @param mixed $variable La variable, arreglo u objeto a inspeccionar.
 * @return string Cadena con la estructura de la variable dentro de etiquetas <pre>.
 * @pre Ninguna.
 * @post Devuelve el volcado de la variable como texto HTML.
 */
function Mostrar($variable)
/*--------------------------------------------------------------------*/
{
    $retorno = "<pre>".var_export($variable, true)."</pre>";
    return $retorno;
}

/*------------------------------------------------------------------*/
/**
 * @brief Ejecuta una sentencia SQL y devuelve los resultados en un objeto.
 * @param string $sentencia Consulta SQL a ejecutar.
 * @param resource $conexion Recurso de la conexión activa.
 * @return object Objeto que contiene la 'cantidad' de registros y los 'datos'.
 * @pre La conexión debe estar abierta y la sentencia ser válida.
 * @post Se libera la memoria de la consulta implícitamente al retornar.
 */
function procesar_query($sentencia, $conexion)
/*--------------------------------------------------------------------*/
{
    $retorno = array();
    $respuesta = pg_query($conexion, $sentencia);
    $Qregistros = pg_num_rows($respuesta);
    for ($i = 0; $i < $Qregistros; $i ++) {
        // $fila = pg_fetch_row($respuesta, $i);
        $retorno[] = pg_fetch_array($respuesta, $i, PGSQL_ASSOC);
    }
    return (object) array('cantidad' => $Qregistros, 'datos' => $retorno);
}

/*------------------------------------------------------------------*/
/**
 * @brief Ejecuta una consulta parametrizada y devuelve filas o un error seguro.
 * @param string $sentencia Sentencia SQL con marcadores $1, $2, etc.
 * @param array $parametros Valores de los parámetros SQL.
 * @param resource $conn Conexión PostgreSQL activa.
 * @return object Cantidad, datos y error si la consulta falla.
 * @pre La sentencia y los parámetros corresponden al esquema de la base.
 * @post Los errores de PostgreSQL no se imprimen directamente.
 */
function consulta_parametrizada($sentencia, $parametros, $conn)
/*--------------------------------------------------------------------*/
{
    $respuesta = @pg_query_params($conn, $sentencia, $parametros);
    if ($respuesta === false) {
        return (object) array(
            'cantidad' => 0,
            'datos' => array(),
            'error' => mensaje_error($conn)
        );
    }

    $filas = array();
    while ($fila = pg_fetch_array($respuesta, null, PGSQL_ASSOC)) {
        $filas[] = $fila;
    }
    return (object) array(
        'cantidad' => count($filas),
        'datos' => $filas,
        'error' => null
    );
}

/*------------------------------------------------------------------*/
/**
 * @brief Ejecuta una sentencia dentro de una transacción y la detiene si falla.
 * @param resource $conn Conexión PostgreSQL activa.
 * @param string $sentencia Sentencia SQL con marcadores $1, $2, etc.
 * @param array $parametros Valores de los parámetros SQL.
 * @return object Cantidad y datos que devolvió la sentencia.
 * @pre Se llama desde la función que recibe en_transaccion.
 * @post Si la sentencia falla, lanza una excepción y en_transaccion revierte todo.
 */
function ejecutar($conn, $sentencia, $parametros = array())
/*--------------------------------------------------------------------*/
{
    $resultado = consulta_parametrizada($sentencia, $parametros, $conn);
    if ($resultado->error !== null) {
        throw new RuntimeException($resultado->error);
    }
    return $resultado;
}

/*------------------------------------------------------------------*/
/**
 * @brief Ejecuta una sentencia con RETURNING y falla si no afectó ninguna fila.
 * @param resource $conn Conexión PostgreSQL activa.
 * @param string $sentencia Sentencia SQL que termina en RETURNING.
 * @param array $parametros Valores de los parámetros SQL.
 * @param string $mensaje Explicación para el usuario si no afectó ninguna fila.
 * @return object Cantidad y datos que devolvió la sentencia.
 * @pre Se llama desde la función que recibe en_transaccion.
 * @post Nunca se informa éxito sobre un registro que ya no existe.
 */
function ejecutar_en_fila($conn, $sentencia, $parametros, $mensaje)
/*--------------------------------------------------------------------*/
{
    $resultado = ejecutar($conn, $sentencia, $parametros);
    if ($resultado->cantidad === 0) {
        throw new RuntimeException($mensaje);
    }
    return $resultado;
}

/*------------------------------------------------------------------*/
/**
 * @brief Ejecuta una función dentro de una transacción y revierte ante errores.
 * @param resource $conn Conexión PostgreSQL activa.
 * @param callable $funcion Operaciones que se ejecutarán en la transacción.
 * @return object Estado (exito), lo que devolvió la función (resultado) y el error.
 * @pre La conexión no tiene otra transacción abierta.
 * @post También captura los fallos de las restricciones diferidas al confirmar.
 */
function en_transaccion($conn, $funcion)
/*--------------------------------------------------------------------*/
{
    if (@pg_query($conn, 'BEGIN') === false) {
        return (object) array('exito' => false, 'error' => mensaje_error($conn));
    }

    try {
        $resultado = $funcion();
    } catch (RuntimeException $excepcion) {
        @pg_query($conn, 'ROLLBACK');
        return (object) array('exito' => false, 'error' => $excepcion->getMessage());
    }

    if (@pg_query($conn, 'COMMIT') === false) {
        $error = mensaje_error($conn);
        @pg_query($conn, 'ROLLBACK');
        return (object) array('exito' => false, 'error' => $error);
    }
    return (object) array('exito' => true, 'resultado' => $resultado, 'error' => null);
}

/*------------------------------------------------------------------*/
/**
 * @brief Traduce errores de la base de datos a mensajes comprensibles.
 * @param resource $conn Conexión PostgreSQL con el último error.
 * @return string Mensaje en español sin detalles técnicos.
 * @pre Ocurrió un error en una consulta o transacción.
 * @post Los mensajes de los triggers se muestran tal como están escritos.
 */
function mensaje_error($conn)
/*--------------------------------------------------------------------*/
{
    $texto_completo = (string) @pg_last_error($conn);
    $texto = preg_replace('/^ERROR:\s*/', '', $texto_completo);
    $texto = trim(preg_replace('/\nCONTEXTO?:.*$/s', '', $texto));

    // PostgreSQL indica en CONTEXT la sentencia que originó el error. Si fue un RAISE de las
    // funciones de sql/04_funciones_triggers.sql, el mensaje ya está redactado para el usuario.
    if (preg_match('/\nCONTEXTO?:.*\bRAISE\b/s', $texto_completo) === 1) {
        return $texto;
    }

    if (stripos($texto, 'insert or update') === 0) {
        return 'Uno de los datos seleccionados no existe.';
    }

    if (stripos($texto, 'update or delete') === 0) {
        $mensajes_eliminacion = array(
            'fk_ordenes_plato' => 'No se puede eliminar el plato porque ya fue pedido.',
            'fk_horarios_mesa' => 'No se puede eliminar la mesa porque tiene horarios asociados.',
            'fk_reservaciones_cliente' => 'No se puede eliminar: tiene reservaciones.',
            'fk_pedidos_cliente' => 'No se puede eliminar el usuario porque tiene pedidos.',
            'fk_pedidos_mesero' => 'No se puede eliminar el empleado porque tiene pedidos.',
            'fk_preparaciones_cocinero' => 'No se puede eliminar: tiene preparaciones registradas.'
        );
        foreach ($mensajes_eliminacion as $restriccion => $mensaje) {
            if (strpos($texto, $restriccion) !== false) {
                return $mensaje;
            }
        }
    }

    $mensajes_restricciones = array(
        'uq_platos_nombre' => 'Ya existe un plato con ese nombre.',
        'ck_usuarios_nombre_no_vacio' => 'El nombre no puede quedar vacío.',
        'ck_reservaciones_cantidad_positiva' => 'La cantidad de personas debe ser mayor que cero.',
        'ck_platos_precio_valido' => 'El precio debe ser un número mayor o igual a cero.',
        'ck_platos_tiempo_positivo' => 'El tiempo de preparación debe ser mayor que cero.',
        'ck_mesas_sillas_positivas' => 'La mesa debe tener al menos una silla.'
    );
    foreach ($mensajes_restricciones as $restriccion => $mensaje) {
        if (strpos($texto, $restriccion) !== false) {
            return $mensaje;
        }
    }
    return 'No fue posible completar la operación. Revise los datos e inténtelo de nuevo.';
}

/*------------------------------------------------------------------*/
/**
 * @brief Escapa texto para insertarlo en una página HTML.
 * @param mixed $texto Dato que se mostrará en el navegador.
 * @return string Texto escapado para HTML.
 * @pre El valor puede venir de la base de datos o de una solicitud.
 * @post Los caracteres especiales no se interpretan como etiquetas.
 */
function h($texto)
/*--------------------------------------------------------------------*/
{
    return htmlspecialchars((string) $texto, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

/*------------------------------------------------------------------*/
/**
 * @brief Devuelve el nombre en español de un estado de reservación.
 * @param int $estado Código almacenado en la base.
 * @return string Etiqueta legible del estado.
 * @pre El código corresponde a una reservación.
 * @post Centraliza las etiquetas que se muestran en la aplicación.
 */
function estado_reservacion($estado)
/*--------------------------------------------------------------------*/
{
    $nombres = array(
        0 => 'Reservada',
        1 => 'Ocupada',
        2 => 'Liberada',
        3 => 'Cancelada'
    );
    return $nombres[(int) $estado] ?? 'Desconocido';
}

/*------------------------------------------------------------------*/
/**
 * @brief Devuelve el nombre en español de un estado de orden o pedido.
 * @param int $estado Código almacenado en la base.
 * @return string Etiqueta legible del estado.
 * @pre El código corresponde a una orden o pedido derivado.
 * @post Centraliza las etiquetas que se muestran en la aplicación.
 */
function estado_orden($estado)
/*--------------------------------------------------------------------*/
{
    $nombres = array(
        0 => 'En preparación',
        1 => 'Listo',
        2 => 'Entregado'
    );
    return $nombres[(int) $estado] ?? 'Desconocido';
}

/*------------------------------------------------------------------*/
/**
 * @brief Genera un mensaje de error con el texto escapado.
 * @param string $mensaje Mensaje que verá el usuario.
 * @return string Párrafo HTML de error.
 * @pre El mensaje puede incluir texto procedente de la base.
 * @post El texto se escapa antes de insertarse en la página.
 */
function mostrar_error($mensaje)
/*--------------------------------------------------------------------*/
{
    return "<p class='mensaje error'>".h($mensaje)."</p>";
}

/*------------------------------------------------------------------*/
/**
 * @brief Genera un mensaje de operación exitosa con el texto escapado.
 * @param string $mensaje Mensaje que verá el usuario.
 * @return string Párrafo HTML de éxito.
 * @pre El mensaje puede incluir texto procedente de la base.
 * @post El texto se escapa antes de insertarse en la página.
 */
function mostrar_exito($mensaje)
/*--------------------------------------------------------------------*/
{
    return "<p class='mensaje exito'>".h($mensaje)."</p>";
}

/*------------------------------------------------------------------*/
/**
 * @brief Convierte el resultado de en_transaccion en un mensaje para el usuario.
 * @param object $operacion Resultado devuelto por en_transaccion.
 * @param string $texto_exito Mensaje que se muestra si la operación se confirmó.
 * @return string Párrafo HTML de éxito o de error.
 * @pre La operación ya terminó.
 * @post El usuario ve el motivo si la operación se revirtió.
 */
function mensaje_operacion($operacion, $texto_exito)
/*--------------------------------------------------------------------*/
{
    if ($operacion->exito) {
        return mostrar_exito($texto_exito);
    }
    return mostrar_error($operacion->error);
}

/*------------------------------------------------------------------*/
/**
 * @brief Indica si la petición actual envía un formulario.
 * @return bool Verdadero si el método HTTP es POST.
 * @pre Ninguna.
 * @post Solo las peticiones POST pueden modificar datos.
 */
function es_envio_formulario()
/*--------------------------------------------------------------------*/
{
    return ($_SERVER['REQUEST_METHOD'] ?? 'GET') === 'POST';
}

/*------------------------------------------------------------------*/
/**
 * @brief Lee un texto recibido en la solicitud.
 * @param array $origen Normalmente $_GET o $_POST.
 * @param string $nombre Nombre del campo.
 * @param string $por_omision Valor si el campo no existe o no es un texto.
 * @return string Texto recibido, sin modificar.
 * @pre Ninguna.
 * @post Un campo enviado como lista (nombre[]=x) se trata como ausente.
 */
function texto_recibido($origen, $nombre, $por_omision = '')
/*--------------------------------------------------------------------*/
{
    $valor = $origen[$nombre] ?? $por_omision;
    return is_string($valor) ? $valor : $por_omision;
}

/*------------------------------------------------------------------*/
/**
 * @brief Lee del formulario una lista de casillas marcadas con valores enteros.
 * @param string $nombre Nombre del campo, sin los corchetes.
 * @return array Enteros sin repetir y ordenados de menor a mayor.
 * @pre El formulario pudo no enviar ninguna casilla.
 * @post Cualquier valor que no sea una lista se trata como lista vacía.
 */
function enteros_marcados($nombre)
/*--------------------------------------------------------------------*/
{
    $marcados = $_POST[$nombre] ?? array();
    if (!is_array($marcados)) {
        return array();
    }
    $enteros = array_unique(array_map('intval', $marcados));
    sort($enteros);
    return $enteros;
}

/*------------------------------------------------------------------*/
/**
 * @brief Comprueba que un texto sea una fecha real en el formato indicado.
 * @param string $texto Fecha recibida en la solicitud.
 * @param string $formato Formato de PHP, por ejemplo Y-m-d.
 * @return bool Verdadero si el texto es una fecha válida en ese formato.
 * @pre Ninguna.
 * @post Rechaza fechas imposibles como 2026-13-45.
 */
function fecha_en_formato($texto, $formato)
/*--------------------------------------------------------------------*/
{
    $fecha = DateTime::createFromFormat($formato, (string) $texto);
    return $fecha !== false && $fecha->format($formato) === $texto;
}

/*------------------------------------------------------------------*/
/**
 * @brief Formatea un timestamp para mostrar fecha y hora hasta minutos.
 * @param string $texto Timestamp recibido desde PostgreSQL.
 * @return string Fecha y hora en formato YYYY-MM-DD HH:MM.
 * @pre El texto contiene una fecha y hora, o está vacío.
 * @post Se omiten segundos, fracciones y zona horaria en la presentación.
 */
function fecha_corta($texto)
/*--------------------------------------------------------------------*/
{
    $marca = strtotime((string) $texto);
    if ($marca === false) {
        return (string) $texto;
    }
    return date('Y-m-d H:i', $marca);
}

/*------------------------------------------------------------------*/
/**
 * @brief Ejecuta una consulta parametrizada y devuelve solo sus filas.
 * @param resource $conn Conexión PostgreSQL activa.
 * @param string $sql Sentencia SQL parametrizada.
 * @param array $parametros Valores de los parámetros.
 * @return array Filas obtenidas; vacío si la consulta falla.
 * @pre La consulta corresponde al esquema existente.
 * @post El código de presentación recibe filas o una lista vacía.
 */
function consulta_filas($conn, $sql, $parametros = array())
/*--------------------------------------------------------------------*/
{
    $resultado = consulta_parametrizada($sql, $parametros, $conn);
    return $resultado->error === null ? $resultado->datos : array();
}

/*------------------------------------------------------------------*/
/**
 * @brief Consulta los usuarios que tienen el rol de cliente.
 * @param resource $conn Conexión PostgreSQL activa.
 * @return array Identificador y nombre de cada cliente, en orden alfabético.
 * @pre Ninguna.
 * @post Los empleados no aparecen en la lista.
 */
function clientes_registrados($conn)
/*--------------------------------------------------------------------*/
{
    return consulta_filas(
        $conn,
        "SELECT u.id,
                u.nombre
           FROM usuarios u
           JOIN actuaciones a ON a.usuario_id = u.id
           JOIN roles r ON r.id = a.rol_id
          WHERE r.nombre = 'cliente'
          ORDER BY u.nombre, u.id"
    );
}

/*------------------------------------------------------------------*/
/**
 * @brief Aplica una función de formato a columnas de un conjunto de filas.
 * @param array $filas Filas asociativas obtenidas de una consulta.
 * @param array $formatos Mapa de columna a función, como 'inicio' => 'fecha_corta'.
 * @return array Las mismas filas con esas columnas formateadas.
 * @pre Las columnas indicadas existen en todas las filas.
 * @post Las demás columnas no cambian.
 */
function formatear_columnas($filas, $formatos)
/*--------------------------------------------------------------------*/
{
    foreach ($filas as $indice => $fila) {
        foreach ($formatos as $columna => $funcion) {
            $filas[$indice][$columna] = $funcion($fila[$columna]);
        }
    }
    return $filas;
}

/*------------------------------------------------------------------*/
/**
 * @brief Construye una tabla HTML escapando encabezados y valores.
 * @param array $columnas Mapa de columna de la consulta a título visible.
 * @param array $filas Filas asociativas de datos.
 * @param string $mensaje_vacio Texto que se muestra si no hay filas.
 * @return string Tabla HTML.
 * @pre Las columnas indicadas existen en las filas.
 * @post Encabezados y celdas siempre coinciden; nada se interpreta como HTML.
 */
function html_tabla($columnas, $filas, $mensaje_vacio = 'Sin registros.')
/*--------------------------------------------------------------------*/
{
    $html = '<table><thead><tr>';
    foreach ($columnas as $titulo) {
        $html .= '<th>'.h($titulo).'</th>';
    }
    $html .= '</tr></thead><tbody>';
    foreach ($filas as $fila) {
        $html .= '<tr>';
        foreach ($columnas as $columna => $titulo) {
            $html .= '<td>'.h($fila[$columna] ?? '').'</td>';
        }
        $html .= '</tr>';
    }
    if (!$filas) {
        $html .= '<tr><td colspan="'.count($columnas).'">'.h($mensaje_vacio).'</td></tr>';
    }
    return $html.'</tbody></table>';
}

/*------------------------------------------------------------------*/
/**
 * @brief Construye las opciones de una lista desplegable a partir de filas.
 * @param array $filas Filas asociativas de datos.
 * @param string $columna_valor Columna que se envía en el formulario.
 * @param string $columna_texto Columna que ve el usuario.
 * @param mixed $seleccionado Valor que debe aparecer seleccionado.
 * @return string Etiquetas option escapadas.
 * @pre Las columnas indicadas existen en las filas.
 * @post Los valores no se interpretan como HTML.
 */
function html_opciones($filas, $columna_valor, $columna_texto, $seleccionado = null)
/*--------------------------------------------------------------------*/
{
    $html = '';
    foreach ($filas as $fila) {
        $marca = (string) $fila[$columna_valor] === (string) $seleccionado ? ' selected' : '';
        $html .= "<option value='".h($fila[$columna_valor])."'$marca>"
               . h($fila[$columna_texto]).'</option>';
    }
    return $html;
}

/*------------------------------------------------------------------*/
/**
 * @brief Construye un campo oculto de formulario.
 * @param string $nombre Nombre del campo.
 * @param mixed $valor Valor del campo.
 * @return string Etiqueta input escapada.
 * @pre Ninguna.
 * @post El valor no se interpreta como HTML.
 */
function campo_oculto($nombre, $valor)
/*--------------------------------------------------------------------*/
{
    return "<input type='hidden' name='".h($nombre)."' value='".h($valor)."'>";
}

?>
