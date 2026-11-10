<?php
//------------------------------------------------------------
ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);
error_reporting(E_ALL);

session_set_cookie_params(array(
    'lifetime' => 0,
    'path' => '/',
    'secure' => isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off',
    'httponly' => true,
    'samesite' => 'Lax'
));
date_default_timezone_set('America/Bogota');
session_start();

require_once("etc/parametros.php");
require_once("lib/libreria.php");
require_once("lib/restaurante.php");
require_once("lib/sesion.php");
require_once("lib/administrador.php");
require_once("lib/maitre.php");
require_once("lib/mesero.php");
require_once("lib/cocinero.php");

//------------------------------------------------------------
$conn = pg_conectar($host, $dbname, $user, $password);
$contenido = "";

$opcion = "";
if (isset($_REQUEST['opcion']))
    $opcion = $_REQUEST['opcion'];

if ($opcion != "") {
    $funcion = "fn_".$opcion;
    if (function_exists($funcion))
        $contenido = $funcion($conn);
    else
        $contenido = fn_menu_opciones($conn);
} else
    $contenido = fn_menu_opciones($conn);

//------------------------------------------------------------
$esqueleto = file_get_contents("esqueleto.html");
$html = sprintf($esqueleto, $contenido);
print $html;

//------------------------------------------------------------
?>
