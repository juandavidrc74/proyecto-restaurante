#!/bin/bash
# Pruebas funcionales de la aplicación por HTTP, con la sesión real de cada rol.
# ATENCIÓN: cambia datos de restaurante_proyecto y al terminar vuelve a cargar sql/05_datos.sql.
# Uso, desde la carpeta del proyecto en la VM: bash pruebas/03_aplicacion.sh --confirmar-borrado
set -uo pipefail

if [ "${1:-}" != "--confirmar-borrado" ]; then
    echo "Este script cambia y recarga los datos de restaurante_proyecto. Use --confirmar-borrado."
    exit 2
fi

BASE=restaurante_proyecto
URL="${URL_APP:-http://localhost/~estudiante/restaurante/}"
CLAVE=restaurante2026
TMP=$(mktemp -d)
FALLIDOS=0
TOTAL=0

sql() { psql -w -X -q -At -d "$BASE" -c "$1" 2>&1; }
caso() { # nombre condición(si/no)
    TOTAL=$((TOTAL + 1))
    if [ "$2" = "si" ]; then
        echo "APROBADO | $1 | ${3:-se cumple}"
    else
        echo "FALLIDO  | $1 ${3:+| $3}"
        FALLIDOS=$((FALLIDOS + 1))
    fi
}
# Por HTTP, PHP escribe los avisos con etiquetas: <b>Warning</b>: ...
AVISOS_PHP='(Warning|Notice|Deprecated|Fatal error|Parse error)(</b>)?:|TypeError'
sin_avisos() { grep -qE "$AVISOS_PHP" <<<"$1" && echo no || echo si; }
tiene() { grep -qF -- "$2" <<<"$1" && echo si || echo no; }
no_tiene() { grep -qF -- "$2" <<<"$1" && echo no || echo si; }
igual() { [ "$1" = "$2" ] && echo si || echo no; }
ver() { curl -g -s --max-time 30 -b "$TMP/$1.jar" -c "$TMP/$1.jar" "$URL?opcion=$2" | tee -a "$TMP/visitadas.html"; }
enviar() { # usuario opcion datos...
    local quien="$1" opcion="$2"; shift 2
    local args=()
    for d in "$@"; do args+=(--data-urlencode "$d"); done
    curl -g -s --max-time 30 -b "$TMP/$quien.jar" -c "$TMP/$quien.jar" "${args[@]}" "$URL?opcion=$opcion" | tee -a "$TMP/visitadas.html"
}
entrar() { enviar "$1" iniciar_sesion "usuario_id=$2" "clave=$CLAVE" > /dev/null; }
# Tramo de una página entre dos textos; separa por <h2> porque el HTML sale en una sola línea.
seccion() { sed 's/<h2>/\n<h2>/g' <<<"$1" | awk -v a="$2" -v b="${3:-}" 'index($0, a) { dentro = 1 } dentro && b != "" && index($0, b) { exit } dentro { print }'; }
mensajes() { grep -oE "class='mensaje [a-z]+'>[^<]*" <<<"$1" | sed -E "s/.*'>//" | head -2 | tr '\n' ' '; }

# Los datos de hoy son relativos a la hora de carga: se cargan de nuevo para que estén vigentes.
psql -w -X -q -d "$BASE" -f sql/05_datos.sql > /dev/null 2>&1

# Usuarios de la carga de datos
rol() { sql "SELECT a.usuario_id FROM actuaciones a JOIN roles r ON r.id = a.rol_id WHERE r.nombre = '$1' ORDER BY 1 LIMIT 1"; }
ADMIN=$(rol administrador)
MAITRE=$(rol maitre)
MESERO=$(sql "SELECT p.mesero_id FROM ordenes o JOIN pedidos p ON p.id = o.pedido_id WHERE o.estado = 1 ORDER BY o.id LIMIT 1")
OTRO_MESERO=$(sql "SELECT a.usuario_id FROM actuaciones a JOIN roles r ON r.id = a.rol_id WHERE r.nombre = 'mesero' AND a.usuario_id <> $MESERO ORDER BY 1 LIMIT 1")
COCINERO=$(sql "SELECT e.cocinero_id FROM especialidades e JOIN ordenes o ON o.plato_id = e.plato_id WHERE o.estado = 0 GROUP BY 1 ORDER BY count(*) DESC, 1 LIMIT 1")
echo "Usuarios: admin=$ADMIN maitre=$MAITRE mesero=$MESERO otro=$OTRO_MESERO cocinero=$COCINERO"

echo "== Sesión y permisos =="
P=$(curl -s "$URL?opcion=")
caso "menú público conserva Desplegar Menu y Realizar Pedido" "$([ "$(tiene "$P" 'Desplegar Menu')" = si ] && [ "$(tiene "$P" 'Realizar Pedido')" = si ] && echo si || echo no)"
P=$(curl -s "$URL?opcion=desplegar_menu")
caso "Desplegar Menu muestra los 24 platos" "$(igual "$(grep -oE "class='PLATO'" <<<"$P" | wc -l)" 24)"
for o in admin_mesas admin_menu admin_empleados admin_especialidades admin_reportes admin_historial maitre_reservaciones maitre_nueva maitre_disponibilidad maitre_modificar maitre_avisos mesero_pedidos mesero_avisos cocinero_ordenes; do
    P=$(curl -s "$URL?opcion=$o")
    caso "sin sesión se rechaza $o" "$(tiene "$P" 'Se requiere iniciar sesión')"
done
enviar intruso iniciar_sesion "usuario_id=$ADMIN" "clave=incorrecta" > "$TMP/x"
caso "clave incorrecta rechazada" "$(tiene "$(cat "$TMP/x")" 'No fue posible iniciar sesión')"
P=$(ver intruso admin_mesas)
caso "tras clave incorrecta no hay sesión" "$(tiene "$P" 'Se requiere iniciar sesión')"
CLIENTE=$(rol cliente)
enviar cliente iniciar_sesion "usuario_id=$CLIENTE" "clave=$CLAVE" > "$TMP/x"
caso "un cliente no puede iniciar sesión" "$(tiene "$(cat "$TMP/x")" 'No fue posible iniciar sesión')"

P=$(enviar auxiliar iniciar_sesion "usuario_id=$ADMIN" "clave=$CLAVE"); caso "al iniciar sesión muestra el menú" "$(tiene "$P" 'Opciones del programa')"
entrar admin "$ADMIN"; entrar maitre "$MAITRE"; entrar mesero "$MESERO"; entrar otro "$OTRO_MESERO"; entrar cocinero "$COCINERO"
P=$(ver admin ""); caso "administrador ve sus accesos" "$(tiene "$P" 'admin_mesas')"; caso "administrador no ve accesos de cocinero" "$(no_tiene "$P" 'cocinero_ordenes')"
P=$(ver cocinero ""); caso "cocinero no ve accesos de administrador" "$(no_tiene "$P" 'admin_mesas')"
for par in "maitre admin_mesas" "maitre admin_reportes" "mesero admin_empleados" "mesero maitre_nueva" "cocinero admin_menu" "cocinero mesero_pedidos" "admin maitre_nueva" "admin cocinero_ordenes" "mesero cocinero_ordenes" "cocinero maitre_reservaciones"; do
    set -- $par
    P=$(ver "$1" "$2")
    caso "$1 no accede a $2" "$(tiene "$P" 'Se requiere iniciar sesión')"
done

ANTES=$(sql "SELECT count(*) FROM mesas")
curl -s --data-urlencode accion=agregar --data-urlencode sillas=4 "$URL?opcion=admin_mesas" > /dev/null
caso "POST sin sesión no agrega mesas" "$(igual "$(sql "SELECT count(*) FROM mesas")" "$ANTES")"
P=$(enviar maitre admin_mesas accion=agregar sillas=4); caso "POST de otro rol no agrega mesas" "$(igual "$(sql "SELECT count(*) FROM mesas")" "$ANTES")"

echo "== Administrador: mesas (PDF 3.1) =="
CUPO=$(sql "SELECT sum(sillas) FROM mesas")
P=$(ver admin admin_mesas); caso "muestra cupo total $CUPO" "$(tiene "$P" "Cupo total: $CUPO")"
P=$(enviar admin admin_mesas accion=agregar sillas=5); N=$(sql "SELECT max(id) FROM mesas")
caso "agregar mesa suma al cupo" "$(tiene "$P" "Cupo total: $((CUPO + 5))")"
P=$(enviar admin admin_mesas accion=modificar "id=$N" sillas=7); caso "modificar sillas" "$(igual "$(sql "SELECT sillas FROM mesas WHERE id = $N")" 7)"
P=$(enviar admin admin_mesas accion=agregar sillas=0); caso "rechaza mesa sin sillas, en español" "$(tiene "$P" 'al menos una silla')"
P=$(enviar admin admin_mesas accion=eliminar "id=$N"); caso "eliminar mesa sin historial" "$(igual "$(sql "SELECT count(*) FROM mesas WHERE id = $N")" 0)"
P=$(enviar admin admin_mesas accion=eliminar id=1); caso "rechaza eliminar mesa con historial, en español" "$(tiene "$P" 'No se puede eliminar la mesa')"
M=$(sql "SELECT h.mesa_id FROM horarios h JOIN reservaciones r ON r.id = h.reservacion_id WHERE r.estado = 1 ORDER BY h.mesa_id LIMIT 1")
P=$(enviar admin admin_mesas accion=modificar "id=$M" sillas=1); caso "rechaza reducir sillas de una mesa en uso" "$(grep -qE 'requiere [0-9]+ sillas' <<<"$P" && echo si || echo no)" "$(mensajes "$P")"
P=$(enviar admin admin_mesas accion=modificar id=999999 sillas=4); caso "modificar una mesa inexistente no informa éxito" "$(tiene "$P" 'ya no existe')"
P=$(enviar admin admin_mesas accion=eliminar id=999999); caso "eliminar una mesa inexistente no informa éxito" "$(tiene "$P" 'ya no existe')"

echo "== Administrador: menú (PDF 3.3) =="
P=$(enviar admin admin_menu accion=agregar "nombre=Plato de prueba" "descripcion=Descripción de prueba" tipo_id=3 tiempo=25 precio=15000)
N=$(sql "SELECT id FROM platos WHERE nombre = 'Plato de prueba'"); caso "agregar plato" "$([ -n "$N" ] && echo si || echo no)"
caso "guarda tiempo y categoría" "$(igual "$(sql "SELECT tiempo || '/' || tipo_id FROM platos WHERE id = ${N:-0}")" '00:25:00/3')"
P=$(ver admin admin_menu); caso "el menú muestra el plato nuevo con su categoría" "$(tiene "$P" '<td>Plato de prueba</td><td>Descripción de prueba</td><td>postre</td><td>25</td>')"
P=$(enviar admin admin_menu accion=modificar "id=$N" "nombre=Plato cambiado" "descripcion=Otra" tipo_id=3 tiempo=30 precio=16000); caso "modificar plato" "$(igual "$(sql "SELECT nombre || '/' || precio FROM platos WHERE id = $N")" 'Plato cambiado/16000')"
P=$(enviar admin admin_menu accion=agregar "nombre=Precio malo" descripcion=x tipo_id=1 tiempo=5 precio=-1); caso "rechaza precio negativo, en español" "$(tiene "$P" 'mayor o igual a cero')" "$(mensajes "$P")"
P=$(enviar admin admin_menu accion=agregar "nombre=Precio raro" descripcion=x tipo_id=1 tiempo=5 precio=NaN); caso "rechaza precio NaN" "$(igual "$(sql "SELECT count(*) FROM platos WHERE nombre = 'Precio raro'")" 0)" "$(mensajes "$P")"
P=$(enviar admin admin_menu accion=eliminar id=999999); caso "eliminar un plato inexistente no informa éxito" "$(tiene "$P" 'ya no existe')"
P=$(ver admin admin_menu); TABLA=$(seccion "$P" 'Administrar menú' 'Agregar plato')
caso "la tabla del menú tiene tantas columnas como encabezados" "$(igual "$(grep -o '<th>' <<<"$TABLA" | wc -l)" "$(sed 's/<\/tr>/\n/g' <<<"$TABLA" | grep '<td>' | head -1 | grep -o '<td>' | wc -l)")"
P=$(enviar admin admin_menu accion=agregar "nombre=  " "descripcion=x" tipo_id=1 tiempo=5 precio=1); caso "rechaza un plato sin nombre" "$(tiene "$P" 'nombre y la descripción')" "$(mensajes "$P")"
P=$(enviar admin admin_menu accion=eliminar "id=$N"); caso "eliminar plato sin pedidos" "$(igual "$(sql "SELECT count(*) FROM platos WHERE id = $N")" 0)"
U=$(sql "SELECT plato_id FROM ordenes ORDER BY id LIMIT 1")
P=$(enviar admin admin_menu accion=eliminar "id=$U"); caso "rechaza eliminar plato ya pedido, en español" "$(tiene "$P" 'ya fue pedido')" "$(mensajes "$P")"

echo "== Administrador: empleados y especialidades (PDF 2 y 4.2) =="
P=$(enviar admin admin_empleados accion=agregar "nombre=Cocinera Nueva" "clave=$CLAVE" rol=cocinero)
N=$(sql "SELECT id FROM usuarios WHERE nombre = 'Cocinera Nueva'"); caso "registrar cocinero" "$([ -n "$N" ] && echo si || echo no)"
caso "la clave se guarda como hash, con fecha" "$(igual "$(sql "SELECT convert_from(clave, 'UTF8') LIKE '\$2y\$%' AND fecha_clave IS NOT NULL FROM usuarios WHERE id = ${N:-0}")" t)"
entrar nueva "${N:-0}"; P=$(ver nueva cocinero_ordenes); caso "el empleado nuevo inicia sesión" "$(tiene "$P" 'Órdenes pendientes')"
caso "sin especialidades no ve órdenes" "$(no_tiene "$P" 'Marcar listo')"
caso "sin órdenes lo dice" "$(tiene "$P" 'No hay órdenes pendientes.')"
PL=$(sql "SELECT plato_id FROM ordenes WHERE estado = 0 ORDER BY id LIMIT 1")
P=$(enviar admin admin_especialidades "cocinero_id=$N" "plato_id[]=$PL"); caso "asignar especialidad" "$(igual "$(sql "SELECT count(*) FROM especialidades WHERE cocinero_id = $N AND plato_id = $PL")" 1)"
P=$(ver nueva cocinero_ordenes); caso "con especialidad ve la orden" "$(tiene "$P" 'Marcar listo')"
P=$(enviar admin admin_especialidades "cocinero_id=$N"); caso "quitar especialidad" "$(igual "$(sql "SELECT count(*) FROM especialidades WHERE cocinero_id = $N")" 0)"
HUELLA=$(sql "SELECT md5(clave) FROM usuarios WHERE id = $N"); P=$(enviar admin admin_empleados accion=modificar "id=$N" "nombre=Cocinera Renombrada" clave=)
caso "modificar el nombre" "$(igual "$(sql "SELECT nombre FROM usuarios WHERE id = $N")" 'Cocinera Renombrada')"
caso "sin escribir clave, la clave no cambia" "$(igual "$(sql "SELECT md5(clave) FROM usuarios WHERE id = $N")" "$HUELLA")"
P=$(enviar admin admin_empleados accion=modificar "id=$N" "nombre=Cocinera Renombrada" clave=otraclave123)
P=$(enviar clave_nueva iniciar_sesion "usuario_id=$N" clave=otraclave123); caso "la clave nueva permite entrar" "$(tiene "$P" 'Sesión iniciada')"
P=$(enviar clave_vieja iniciar_sesion "usuario_id=$N" "clave=$CLAVE"); caso "la clave anterior ya no sirve" "$(tiene "$P" 'No fue posible iniciar sesión')"
P=$(enviar admin admin_empleados accion=eliminar "id=$N"); caso "eliminar empleado sin historial" "$(igual "$(sql "SELECT count(*) FROM usuarios WHERE id = $N")" 0)"
P=$(enviar admin admin_empleados accion=eliminar "id=$MESERO"); caso "rechaza eliminar empleado con historial" "$(igual "$(sql "SELECT count(*) FROM usuarios WHERE id = $MESERO")" 1)"
caso "ese rechazo está en español" "$(tiene "$P" 'No se puede eliminar')" "$(mensajes "$P")"
P=$(enviar admin admin_empleados accion=eliminar "id=$ADMIN"); caso "el administrador no se elimina a sí mismo" "$(igual "$(sql "SELECT count(*) FROM usuarios WHERE id = $ADMIN")" 1)"
caso "ese rechazo lo explica" "$(tiene "$P" 'propia cuenta')" "$(mensajes "$P")"
P=$(ver admin admin_mesas); caso "la sesión del administrador sigue activa" "$(tiene "$P" 'Cupo total')"
P=$(enviar admin admin_empleados accion=agregar "nombre=Sin Clave" clave= rol=mesero); caso "rechaza empleado sin clave" "$(igual "$(sql "SELECT count(*) FROM usuarios WHERE nombre = 'Sin Clave'")" 0)"
caso "ese rechazo pide la clave" "$(tiene "$P" 'La clave es obligatoria')" "$(mensajes "$P")"
P=$(enviar admin admin_empleados accion=agregar "nombre=Otro Admin" "clave=$CLAVE" rol=administrador); caso "solo registra maitres, meseros y cocineros" "$(igual "$(sql "SELECT count(*) FROM usuarios WHERE nombre = 'Otro Admin'")" 0)"
caso "ese rechazo pide un rol válido" "$(tiene "$P" 'rol de empleado válido')" "$(mensajes "$P")"
NOMBRE_CLIENTE=$(sql "SELECT nombre FROM usuarios WHERE id = $CLIENTE")
P=$(enviar admin admin_empleados accion=modificar "id=$CLIENTE" "nombre=Cambiado" clave=); caso "modificar no actúa sobre clientes" "$(igual "$(sql "SELECT nombre FROM usuarios WHERE id = $CLIENTE")" "$NOMBRE_CLIENTE")" "$(mensajes "$P")"
caso "ese rechazo pide un empleado válido" "$(tiene "$P" 'empleado válido')"
CS=$(sql "WITH u AS (INSERT INTO usuarios (nombre) VALUES ('Cliente sin historial') RETURNING id) INSERT INTO actuaciones (usuario_id, rol_id) SELECT u.id, r.id FROM u, roles r WHERE r.nombre = 'cliente' RETURNING usuario_id")
P=$(enviar admin admin_empleados accion=eliminar "id=$CS"); caso "eliminar no actúa sobre un cliente sin historial" "$(igual "$(sql "SELECT count(*) FROM usuarios WHERE id = $CS")" 1)" "$(mensajes "$P")"
P=$(ver admin admin_empleados); caso "la lista solo muestra empleados gestionados" "$([ "$(no_tiene "$P" '<td>administrador</td>')" = si ] && [ "$(no_tiene "$P" '<td>cliente</td>')" = si ] && echo si || echo no)"
P=$(enviar admin admin_empleados accion=agregar "nombre=Mesero Sin Pedidos" "clave=$CLAVE" rol=mesero); MN=$(sql "SELECT id FROM usuarios WHERE nombre = 'Mesero Sin Pedidos'")
entrar mesero_nuevo "${MN:-0}"; P=$(ver mesero_nuevo mesero_pedidos); caso "mesero sin pedidos lo ve indicado" "$(tiene "$P" 'No hay pedidos activos.')"
P=$(enviar admin admin_empleados accion=eliminar "id=${MN:-0}"); caso "eliminar al mesero sin pedidos" "$(igual "$(sql "SELECT count(*) FROM usuarios WHERE nombre = 'Mesero Sin Pedidos'")" 0)"

echo "== Maitre: reservaciones (PDF 3.2) =="
F=2027-03-03
P=$(enviar maitre maitre_nueva cliente_id=0 "cliente_nuevo=Cliente Prueba" cantidad=3 "inicio=${F}T18:00" duracion=90 "mesa_id[]=2")
R=$(sql "SELECT r.id FROM reservaciones r JOIN usuarios u ON u.id = r.cliente_id WHERE u.nombre = 'Cliente Prueba'"); caso "crear reservación con cliente nuevo" "$([ -n "$R" ] && echo si || echo no)" "$(mensajes "$P")"
caso "tras crear enlaza a las reservaciones de ese día" "$(tiene "$P" "maitre_reservaciones&amp;dia=$F")"
CL=$(sql "SELECT cliente_id FROM reservaciones WHERE id = ${R:-0}")
caso "el cliente nuevo tiene rol cliente y no tiene clave" "$(igual "$(sql "SELECT tiene_rol($CL, 'cliente') AND u.clave IS NULL FROM usuarios u WHERE u.id = $CL")" t)"
caso "el horario queda en la partición de 2027" "$(igual "$(sql "SELECT tableoid::regclass FROM horarios WHERE reservacion_id = ${R:-0}")" horarios_3)"
P=$(enviar maitre maitre_nueva "cliente_id=$CL" cliente_nuevo= cantidad=2 "inicio=${F}T19:00" duracion=60 "mesa_id[]=2"); caso "rechaza cruce en la misma mesa" "$(tiene "$P" 'ya tiene una reservación activa')" "$(mensajes "$P")"
P=$(enviar maitre maitre_nueva "cliente_id=$CL" cliente_nuevo= cantidad=2 "inicio=${F}T20:00" duracion=60 "mesa_id[]=2"); caso "permite ventana contigua, a las 2 horas exactas" "$(tiene "$P" 'Reservación registrada')" "$(mensajes "$P")"
P=$(enviar maitre maitre_nueva "cliente_id=$CL" cliente_nuevo= cantidad=5 "inicio=${F}T12:00" duracion=60 "mesa_id[]=2"); caso "rechaza sillas insuficientes" "$(tiene "$P" 'requiere 5 sillas')" "$(mensajes "$P")"
P=$(enviar maitre maitre_nueva "cliente_id=$CL" cliente_nuevo= cantidad=10 "inicio=${F}T12:00" duracion=60 "mesa_id[]=3" "mesa_id[]=4"); caso "permite una reservación con dos mesas" "$(tiene "$P" 'Reservación registrada')" "$(mensajes "$P")"
TODAS=(); for i in $(sql "SELECT id FROM mesas ORDER BY id"); do TODAS+=("mesa_id[]=$i"); done
P=$(enviar maitre maitre_nueva "cliente_id=$CL" cliente_nuevo= "cantidad=$((CUPO + 1))" "inicio=2027-03-10T12:00" duracion=60 "${TODAS[@]}"); caso "rechaza superar el cupo total" "$(tiene "$P" 'cupo del restaurante se supera')" "$(mensajes "$P")"
P=$(enviar maitre maitre_nueva "cliente_id=$CL" cliente_nuevo= cantidad=2 "inicio=2027-03-11T12:00" duracion=60); caso "rechaza reservación sin mesa" "$(tiene "$P" 'al menos una mesa')" "$(mensajes "$P")"
P=$(enviar maitre maitre_nueva "cliente_id=$CL" cliente_nuevo= cantidad=2 "inicio=2027-02-31T12:00" duracion=60 "mesa_id[]=1"); caso "rechaza una fecha imposible" "$(tiene "$P" 'fecha y hora válidas')" "$(mensajes "$P")"
caso "el error conserva lo escrito en el formulario" "$(tiene "$P" "value='1' checked")"
ANTES=$(sql "SELECT count(*) FROM reservaciones")
P=$(enviar maitre maitre_nueva cliente_id=0 cliente_nuevo= cantidad=2 "inicio=2027-03-11T12:00" duracion=60 "mesa_id[]=1"); caso "rechaza reservación sin cliente, con mensaje claro" "$(tiene "$P" 'Seleccione un cliente o escriba')" "$(mensajes "$P")"
caso "sin cliente no se crea ninguna reservación" "$(igual "$(sql "SELECT count(*) FROM reservaciones")" "$ANTES")"
caso "ese mensaje no habla de eliminar" "$(no_tiene "$P" 'No se puede eliminar')"
P=$(enviar maitre maitre_nueva "cliente_id=$CL" cliente_nuevo= cantidad=2 "inicio=2027-03-11T12:00" duracion=120 "mesa_id[]=1"); caso "rechaza duración de 2 horas" "$(tiene "$P" 'duración')" "$(mensajes "$P")"
P=$(enviar maitre maitre_nueva "cliente_id=$CL" cliente_nuevo= cantidad=2 "inicio=2027-03-11T12:00" duracion=45 "mesa_id[]=1"); caso "duración personalizable" "$(igual "$(sql "SELECT duracion FROM horarios WHERE inicio = '2027-03-11 12:00' AND mesa_id = 1")" 00:45:00)"

echo "== Maitre: disponibilidad y modificación =="
P=$(ver maitre "maitre_disponibilidad&instante=${F}T17:00"); caso "disponibilidad oculta una mesa con reserva dentro de 2 horas" "$(no_tiene "$P" '<td>2</td><td>4</td>')"
caso "disponibilidad muestra una mesa libre" "$(tiene "$P" '<td>5</td><td>2</td>')"
caso "disponibilidad muestra cupo" "$(tiene "$P" "de $CUPO")"
P=$(ver maitre "maitre_disponibilidad&instante=basura"); caso "disponibilidad avisa de una fecha inválida" "$(tiene "$P" 'fecha y hora válidas')"
P=$(ver maitre "maitre_modificar&reservacion_id=$R"); caso "la pantalla de modificar precarga la duración" "$(tiene "$P" "value='90'")"
P=$(enviar maitre "maitre_modificar&reservacion_id=$R" "reservacion_id=$R" cantidad=4 "inicio=${F}T18:00" duracion=100 "mesa_id[]=2"); caso "modificar cantidad y duración" "$(igual "$(sql "SELECT r.cantidad || '/' || h.duracion FROM reservaciones r JOIN horarios h ON h.reservacion_id = r.id WHERE r.id = $R")" 4/01:40:00)" "$(mensajes "$P")"
P=$(enviar maitre "maitre_modificar&reservacion_id=$R" "reservacion_id=$R" cantidad=4 "inicio=2026-12-20T18:00" duracion=100 "mesa_id[]=2"); caso "mover de fecha cambia de partición" "$(igual "$(sql "SELECT tableoid::regclass FROM horarios WHERE reservacion_id = $R")" horarios_2)" "$(mensajes "$P")"
P=$(enviar maitre "maitre_modificar&reservacion_id=$R" "reservacion_id=$R" cantidad=99 "inicio=2026-12-20T18:00" duracion=100 "mesa_id[]=2"); caso "modificar respeta sillas y deshace todo" "$(igual "$(sql "SELECT cantidad FROM reservaciones WHERE id = $R")" 4)"

echo "== Maitre: estados =="
D=$(date +%F)
P=$(ver maitre "maitre_reservaciones&dia=2026-12-20"); caso "lista reservaciones de un día" "$(tiene "$P" 'Cliente Prueba')"
caso "una reservada no ofrece Liberar" "$(no_tiene "$P" "value='liberar'")"
caso "una reservada ofrece Marcar ocupada y Cancelar" "$([ "$(tiene "$P" "value='ocupar'")" = si ] && [ "$(tiene "$P" "value='cancelar'")" = si ] && echo si || echo no)"
P=$(enviar maitre "maitre_reservaciones&dia=2026-12-20" "reservacion_id=$R" accion=ocupar); caso "marcar ocupada" "$(igual "$(sql "SELECT estado FROM reservaciones WHERE id = $R")" 1)"
caso "una ocupada ofrece Liberar y Cancelar, no Marcar ocupada" "$([ "$(tiene "$P" "value='liberar'")" = si ] && [ "$(tiene "$P" "value='cancelar'")" = si ] && [ "$(no_tiene "$P" "value='ocupar'")" = si ] && echo si || echo no)"
P=$(enviar maitre "maitre_reservaciones&dia=2026-12-20" "reservacion_id=$R" accion=liberar); caso "liberar" "$(igual "$(sql "SELECT estado FROM reservaciones WHERE id = $R")" 2)"
caso "una liberada no ofrece acciones" "$(no_tiene "$P" "value='cancelar'")"
P=$(enviar maitre maitre_reservaciones reservacion_id=999999 accion=cancelar); caso "cambiar el estado de una reservación inexistente no informa éxito" "$(tiene "$P" 'ya no existe')"
P=$(enviar maitre "maitre_reservaciones&dia=2026-12-20" "reservacion_id=$R" accion=cancelar); caso "rechaza cambiar una liberada, en español y sin números de estado" "$([ "$(igual "$(sql "SELECT estado FROM reservaciones WHERE id = $R")" 2)" = si ] && [ "$(no_tiene "$P" '2 a 3')" = si ] && echo si || echo no)" "$(mensajes "$P")"
P=$(enviar maitre maitre_nueva "cliente_id=$CL" cliente_nuevo= cantidad=2 "inicio=2027-05-05T12:00" duracion=60 "mesa_id[]=1"); R2=$(sql "SELECT reservacion_id FROM horarios WHERE inicio = '2027-05-05 12:00'")
P=$(enviar maitre "maitre_reservaciones&dia=2027-05-05" "reservacion_id=$R2" accion=cancelar); caso "cancelar" "$(igual "$(sql "SELECT estado FROM reservaciones WHERE id = $R2")" 3)"
P=$(enviar maitre maitre_nueva "cliente_id=$CL" cliente_nuevo= cantidad=2 "inicio=2027-05-05T12:00" duracion=60 "mesa_id[]=1"); caso "la mesa de una cancelada queda libre" "$(tiene "$P" 'Reservación registrada')" "$(mensajes "$P")"
MA=$(sql "SELECT r.id FROM reservaciones r JOIN horarios h ON h.reservacion_id = r.id WHERE r.estado = 1 AND EXISTS (SELECT 1 FROM ordenes o JOIN pedidos p ON p.id = o.pedido_id WHERE p.cliente_id = r.cliente_id AND o.solicitado::timestamp >= h.inicio AND o.solicitado::timestamp < h.inicio + INTERVAL '2 hours') ORDER BY 1 LIMIT 1")
P=$(enviar maitre maitre_reservaciones "reservacion_id=$MA" accion=cancelar); caso "rechaza cancelar una reservación con pedidos" "$(tiene "$P" 'tiene pedidos')" "$(mensajes "$P")"

echo "== Aviso al maitre (PDF 4.1) =="
PROX=$(sql "SELECT to_char(LOCALTIMESTAMP + INTERVAL '10 minutes', 'YYYY-MM-DD\"T\"HH24:MI')")
LIBRE=$(sql "SELECT m.id FROM mesas m WHERE NOT EXISTS (SELECT 1 FROM horarios h JOIN reservaciones r ON r.id = h.reservacion_id WHERE h.mesa_id = m.id AND r.estado IN (0,1) AND h.inicio > LOCALTIMESTAMP - INTERVAL '2 hours' AND h.inicio < LOCALTIMESTAMP + INTERVAL '3 hours') ORDER BY m.sillas DESC, m.id LIMIT 1")
P=$(enviar maitre maitre_nueva cliente_id=0 "cliente_nuevo=Cliente Aviso" cantidad=1 "inicio=$PROX" duracion=60 "mesa_id[]=$LIBRE")
P=$(ver maitre maitre_avisos); caso "avisa de una reservación próxima" "$(tiene "$P" 'Cliente Aviso')" "$(mensajes "$P")"
caso "el bloque tiene id y opción para actualizarse" "$(tiene "$P" "data-opcion='maitre_avisos'")"
LEJOS=$(sql "SELECT to_char(LOCALTIMESTAMP + INTERVAL '90 minutes', 'YYYY-MM-DD\"T\"HH24:MI')")
LIBRE2=$(sql "SELECT m.id FROM mesas m WHERE m.id <> $LIBRE AND NOT EXISTS (SELECT 1 FROM horarios h JOIN reservaciones r ON r.id = h.reservacion_id WHERE h.mesa_id = m.id AND r.estado IN (0,1) AND h.inicio > LOCALTIMESTAMP - INTERVAL '1 hour' AND h.inicio < LOCALTIMESTAMP + INTERVAL '4 hours') ORDER BY m.sillas DESC, m.id LIMIT 1")
P=$(enviar maitre maitre_nueva cliente_id=0 "cliente_nuevo=Cliente Lejano" cantidad=1 "inicio=$LEJOS" duracion=60 "mesa_id[]=$LIBRE2")
caso "la reservación lejana sí se creó" "$(igual "$(sql "SELECT count(*) FROM reservaciones r JOIN usuarios u ON u.id = r.cliente_id WHERE u.nombre = 'Cliente Lejano'")" 1)" "$(mensajes "$P")"
P=$(ver maitre maitre_avisos); caso "no avisa de una reservación lejana" "$(no_tiene "$P" 'Cliente Lejano')"

echo "== Cocinero (PDF 2) =="
P=$(ver cocinero cocinero_ordenes)
ESPERADO=$(sql "SELECT count(*) FROM especialidades e JOIN ordenes o ON o.plato_id = e.plato_id AND o.estado = 0 WHERE e.cocinero_id = $COCINERO")
caso "solo ve órdenes de sus especialidades ($ESPERADO)" "$(igual "$(grep -oF 'Marcar listo' <<<"$P" | wc -l)" "$ESPERADO")"
ORDEN_SQL=$(sql "SELECT o.id FROM especialidades e JOIN platos p ON p.id = e.plato_id JOIN ordenes o ON o.plato_id = p.id AND o.estado = 0 WHERE e.cocinero_id = $COCINERO ORDER BY p.tiempo DESC, o.solicitado, o.id" | tr '\n' ' ')
ORDEN_WEB=$(grep -oE "name=.orden_id. value=.[0-9]+" <<<"$P" | grep -oE '[0-9]+$' | tr '\n' ' ')
caso "las más demoradas primero" "$(igual "$ORDEN_WEB" "$ORDEN_SQL")" "web: $ORDEN_WEB sql: $ORDEN_SQL"
O1=$(awk '{print $1}' <<<"$ORDEN_SQL")
P=$(enviar cocinero cocinero_ordenes "orden_id=$O1" cocinero_id=1); caso "marcar listo" "$(igual "$(sql "SELECT estado FROM ordenes WHERE id = $O1")" 1)" "$(mensajes "$P")"
caso "la preparación queda a nombre de la sesión, no del formulario" "$(igual "$(sql "SELECT cocinero_id FROM preparaciones WHERE orden_id = $O1")" "$COCINERO")"
P=$(enviar cocinero cocinero_ordenes "orden_id=$O1"); caso "no marca dos veces la misma orden" "$(igual "$(sql "SELECT count(*) FROM preparaciones WHERE orden_id = $O1")" 1)"
O2=$(sql "SELECT o.id FROM ordenes o WHERE o.estado = 0 AND NOT EXISTS (SELECT 1 FROM especialidades e WHERE e.plato_id = o.plato_id AND e.cocinero_id = $COCINERO) ORDER BY o.id LIMIT 1")
if [ -n "$O2" ]; then
    P=$(enviar cocinero cocinero_ordenes "orden_id=$O2"); caso "no prepara un plato sin especialidad" "$(tiene "$P" 'no tiene especialidad')" "$(mensajes "$P")"
fi

echo "== Mesero: entrega y aviso (PDF 3.5 y 4.1) =="
OM=$(sql "SELECT p.mesero_id FROM ordenes o JOIN pedidos p ON p.id = o.pedido_id WHERE o.id = $O1")
entrar duenio "$OM"
P=$(ver duenio mesero_avisos); caso "avisa al mesero cuando la orden está lista" "$(tiene "$P" ">$O1<")"
caso "el aviso tiene id y opción para actualizarse" "$(tiene "$P" "data-opcion='mesero_avisos'")"
caso "el aviso dice la mesa de la orden" "$(tiene "$P" "<td>$O1</td><td>$(sql "SELECT pedido_id FROM ordenes WHERE id = $O1")</td><td>$(sql "SELECT mesa_de_pedido(pedido_id) FROM ordenes WHERE id = $O1")</td>")"
caso "el aviso trae el botón de entrega, para que aparezca sin recargar" "$(tiene "$P" "Entregar orden $O1")"
AJENO=$(sql "SELECT a.usuario_id FROM actuaciones a JOIN roles r ON r.id = a.rol_id WHERE r.nombre = 'mesero' AND a.usuario_id <> $OM ORDER BY 1 LIMIT 1"); entrar ajeno "$AJENO"
P=$(ver ajeno mesero_avisos); caso "no avisa a otro mesero" "$(no_tiene "$P" ">$O1<")"
P=$(enviar ajeno mesero_pedidos "orden_id=$O1"); caso "otro mesero no puede entregarla" "$(igual "$(sql "SELECT estado FROM ordenes WHERE id = $O1")" 1)"
SOL=$(sql "SELECT o.id FROM ordenes o JOIN pedidos p ON p.id = o.pedido_id WHERE p.mesero_id = $OM AND o.estado = 0 ORDER BY 1 LIMIT 1")
if [ -n "$SOL" ]; then
    P=$(enviar duenio mesero_pedidos "orden_id=$SOL"); caso "no entrega una orden sin preparar" "$(igual "$(sql "SELECT estado FROM ordenes WHERE id = $SOL")" 0)"
fi
P=$(ver duenio mesero_pedidos); caso "ofrece entregar la orden lista" "$(tiene "$P" "value='$O1'")"
caso "el botón dice qué orden entrega" "$(tiene "$P" "Entregar orden $O1")"
P=$(enviar duenio mesero_pedidos "orden_id=$O1"); caso "registrar la entrega" "$(igual "$(sql "SELECT estado FROM ordenes WHERE id = $O1")" 2)" "$(mensajes "$P")"
P=$(ver duenio mesero_avisos); caso "el aviso desaparece tras entregar" "$(no_tiene "$P" ">$O1<")"

echo "== Mesero: pedidos (PDF 3.4) =="
P=$(curl -s "$URL?opcion=realizar_pedidos"); MV=$(sql "SELECT h.mesa_id FROM horarios h JOIN reservaciones r ON r.id = h.reservacion_id WHERE r.estado = 1 AND h.inicio <= LOCALTIMESTAMP AND h.inicio > LOCALTIMESTAMP - INTERVAL '2 hours' ORDER BY 1 LIMIT 1")
caso "lista la mesa con reservación vigente" "$(tiene "$P" "mesa_id=$MV")"
caso "no lista una mesa cuya reservación es más tarde" "$(no_tiene "$P" 'Cliente Lejano')"
SIN_FORMULARIO=0
for M in $(grep -oE 'mesa_id=[0-9]+' <<<"$P" | grep -oE '[0-9]+$' | sort -un); do
    [ "$(tiene "$(ver mesero "realizar_pedidos&mesa_id=$M")" 'cantidad[')" = si ] || SIN_FORMULARIO=$((SIN_FORMULARIO + 1))
done
caso "todas las mesas listadas abren el formulario de pedido" "$(igual "$SIN_FORMULARIO" 0)" "$SIN_FORMULARIO sin formulario"
A=$(sql "SELECT id FROM platos ORDER BY id LIMIT 1"); B=$(sql "SELECT id FROM platos ORDER BY id DESC LIMIT 1")
ANTES=$(sql "SELECT count(*) FROM pedidos")
P=$(curl -s --data-urlencode "cantidad[$A]=1" "$URL?opcion=realizar_pedidos&mesa_id=$MV"); caso "sin sesión de mesero se rechaza el pedido" "$(tiene "$P" 'Se requiere iniciar sesión')"
caso "sin sesión de mesero no se registra el pedido" "$(igual "$(sql "SELECT count(*) FROM pedidos")" "$ANTES")"
P=$(ver mesero "realizar_pedidos&mesa_id=$MV"); caso "muestra el menú para pedir" "$(tiene "$P" 'cantidad[')"
caso "un solo botón de volver al menú" "$(igual "$(grep -oF 'Menu del programa' <<<"$P" | wc -l)" 1)"
caso "el formulario de pedido también muestra el bloque de avisos" "$(tiene "$P" "data-opcion='mesero_avisos'")"
P=$(enviar mesero "realizar_pedidos&mesa_id=$MV" "cantidad[$A]=0"); caso "rechaza un pedido sin platos" "$(igual "$(sql "SELECT count(*) FROM pedidos")" "$ANTES")"
P=$(enviar mesero "realizar_pedidos&mesa_id=$MV" "cantidad[$A]=2" "cantidad[$B]=1"); PED=$(sql "SELECT max(id) FROM pedidos")
caso "registra un pedido con varios platos y cantidades" "$(igual "$(sql "SELECT count(*) || '/' || sum(cantidad) FROM ordenes WHERE pedido_id = $PED")" 2/3)" "$(mensajes "$P")"
caso "el pedido queda en la mesa correcta" "$(igual "$(sql "SELECT mesa_id FROM pedidos_detalle WHERE pedido_id = $PED")" "$MV")"
caso "el pedido queda a nombre del mesero de la sesión" "$(igual "$(sql "SELECT mesero_id FROM pedidos WHERE id = $PED")" "$MESERO")"
caso "el cliente es el de la reservación de esa mesa" "$(igual "$(sql "SELECT count(*) FROM pedidos p JOIN reservaciones r ON r.cliente_id = p.cliente_id JOIN horarios h ON h.reservacion_id = r.id WHERE p.id = $PED AND h.mesa_id = $MV AND r.estado = 1")" 1)"
P=$(ver mesero mesero_pedidos); caso "lo ve en sus pedidos con estado" "$(tiene "$P" "Pedido $PED")"
MF=$(sql "SELECT m.id FROM mesas m WHERE NOT EXISTS (SELECT 1 FROM horarios h JOIN reservaciones r ON r.id = h.reservacion_id WHERE h.mesa_id = m.id AND r.estado IN (0,1) AND h.inicio <= LOCALTIMESTAMP AND h.inicio > LOCALTIMESTAMP - INTERVAL '2 hours') ORDER BY m.id LIMIT 1")
ANTES=$(sql "SELECT count(*) FROM pedidos"); P=$(enviar mesero "realizar_pedidos&mesa_id=$MF" "cantidad[$A]=1"); caso "rechaza pedir en una mesa sin reservación vigente" "$(igual "$(sql "SELECT count(*) FROM pedidos")" "$ANTES")"

echo "== Cocinero: orden por tiempo de preparación (PDF 2) =="
read -r CT RAPIDO LENTO <<<"$(sql "SELECT e1.cocinero_id, e1.plato_id, e2.plato_id FROM especialidades e1 JOIN especialidades e2 ON e2.cocinero_id = e1.cocinero_id JOIN platos p1 ON p1.id = e1.plato_id JOIN platos p2 ON p2.id = e2.plato_id WHERE p1.tiempo < p2.tiempo ORDER BY 1, 2, 3 LIMIT 1" | tr '|' ' ')"
P=$(enviar mesero "realizar_pedidos&mesa_id=$MV" "cantidad[$RAPIDO]=1"); O_RAPIDA=$(sql "SELECT max(id) FROM ordenes")
P=$(enviar mesero "realizar_pedidos&mesa_id=$MV" "cantidad[$LENTO]=1"); O_LENTA=$(sql "SELECT max(id) FROM ordenes")
entrar por_tiempo "$CT"; P=$(ver por_tiempo cocinero_ordenes)
IDS=$(grep -oE "name='orden_id' value='[0-9]+" <<<"$P" | grep -oE '[0-9]+$')
POS_LENTA=$(grep -nx "$O_LENTA" <<<"$IDS" | cut -d: -f1); POS_RAPIDA=$(grep -nx "$O_RAPIDA" <<<"$IDS" | cut -d: -f1)
caso "el plato más demorado sale primero, aunque se pidió después" "$([ -n "$POS_LENTA" ] && [ -n "$POS_RAPIDA" ] && [ "$POS_LENTA" -lt "$POS_RAPIDA" ] && echo si || echo no)" "posiciones $POS_LENTA y $POS_RAPIDA"
MINUTOS=$(grep -oE 'preparación [0-9]+ min' <<<"$P" | grep -oE '[0-9]+')
caso "los tiempos de preparación nunca aumentan en la lista" "$(igual "$MINUTOS" "$(sort -rn <<<"$MINUTOS")")"

echo "== Estado del pedido (PDF 3.4 y 3.5) =="
P=$(enviar mesero "realizar_pedidos&mesa_id=$MV" "cantidad[$RAPIDO]=1" "cantidad[$LENTO]=1"); PE=$(sql "SELECT max(id) FROM pedidos")
read -r OE1 OE2 <<<"$(sql "SELECT id FROM ordenes WHERE pedido_id = $PE ORDER BY id" | tr '\n' ' ')"
estado_en_pantalla() { ver mesero mesero_pedidos | sed 's/<section/\n<section/g' | grep -F "<h2>Pedido $PE ·" | grep -oE '· [^·<]+</p>' | head -1 | sed -E 's/· //; s#</p>##'; }
caso "un pedido nuevo está En preparación" "$(igual "$(estado_en_pantalla)" 'En preparación')"
P=$(enviar por_tiempo cocinero_ordenes "orden_id=$OE1"); caso "con una orden lista, el pedido sigue En preparación" "$(igual "$(estado_en_pantalla)" 'En preparación')" "$(mensajes "$P")"
P=$(enviar por_tiempo cocinero_ordenes "orden_id=$OE2"); caso "con todas las órdenes listas, el pedido está Listo" "$(igual "$(estado_en_pantalla)" 'Listo')" "$(mensajes "$P")"
P=$(enviar mesero mesero_pedidos "orden_id=$OE1"); caso "con una orden entregada, el pedido sigue Listo" "$(igual "$(estado_en_pantalla)" 'Listo')" "$(mensajes "$P")"
P=$(enviar mesero mesero_pedidos "orden_id=$OE2"); caso "con todas las órdenes entregadas, el pedido está Entregado" "$(igual "$(estado_en_pantalla)" 'Entregado')" "$(mensajes "$P")"
caso "las órdenes de ese pedido muestran su estado" "$(igual "$(ver mesero mesero_pedidos | sed 's/<section/\n<section/g' | grep -F "<h2>Pedido $PE ·" | grep -o '<td>Entregado</td>' | wc -l)" 2)"

echo "== Maitre: modificar una reservación que ya tiene pedidos (PDF 2) =="
RM=$(sql "SELECT h.reservacion_id FROM horarios h JOIN reservaciones r ON r.id = h.reservacion_id WHERE h.mesa_id = $MV AND r.estado = 1 AND h.inicio <= LOCALTIMESTAMP AND h.inicio > LOCALTIMESTAMP - INTERVAL '2 hours'")
INICIO_RM=$(sql "SELECT to_char(inicio, 'YYYY-MM-DD\"T\"HH24:MI') FROM horarios WHERE reservacion_id = $RM LIMIT 1")
CANT_RM=$(sql "SELECT cantidad FROM reservaciones WHERE id = $RM")
EXTRA=$(sql "SELECT m.id FROM mesas m WHERE NOT EXISTS (SELECT 1 FROM horarios h JOIN reservaciones r ON r.id = h.reservacion_id WHERE h.mesa_id = m.id AND r.estado IN (0, 1) AND h.inicio > '${INICIO_RM/T/ }'::TIMESTAMP - INTERVAL '2 hours' AND h.inicio < '${INICIO_RM/T/ }'::TIMESTAMP + INTERVAL '2 hours') ORDER BY m.id DESC LIMIT 1")
P=$(enviar maitre "maitre_modificar&reservacion_id=$RM" "reservacion_id=$RM" "cantidad=$CANT_RM" "inicio=$INICIO_RM" duracion=100 "mesa_id[]=$MV" "mesa_id[]=$EXTRA")
caso "agrega una mesa a una reservación con pedidos" "$(igual "$(sql "SELECT count(*) FROM horarios WHERE reservacion_id = $RM")" 2)" "$(mensajes "$P")"
caso "cambia la duración de una reservación con pedidos" "$(igual "$(sql "SELECT DISTINCT duracion FROM horarios WHERE reservacion_id = $RM")" 01:40:00)"
FOTO_RM=$(sql "SELECT string_agg(mesa_id || ' ' || inicio || ' ' || duracion, ',' ORDER BY mesa_id) FROM horarios WHERE reservacion_id = $RM")
P=$(enviar maitre "maitre_modificar&reservacion_id=$RM" "reservacion_id=$RM" "cantidad=$CANT_RM" "inicio=$INICIO_RM" duracion=100 "mesa_id[]=$EXTRA")
caso "no quita la mesa del pedido" "$(tiene "$P" 'tiene pedidos asociados')" "$(mensajes "$P")"
P=$(enviar maitre "maitre_modificar&reservacion_id=$RM" "reservacion_id=$RM" "cantidad=$CANT_RM" "inicio=2027-06-01T12:00" duracion=100 "mesa_id[]=$MV")
caso "no mueve de hora una reservación con pedidos" "$(tiene "$P" 'tiene pedidos asociados')" "$(mensajes "$P")"
caso "esos rechazos dejan la reservación como estaba" "$(igual "$(sql "SELECT string_agg(mesa_id || ' ' || inicio || ' ' || duracion, ',' ORDER BY mesa_id) FROM horarios WHERE reservacion_id = $RM")" "$FOTO_RM")"
caso "la mesa agregada tiene un número mayor, como requiere el caso siguiente" "$([ "$EXTRA" -gt "$MV" ] && echo si || echo no)" "mesas $MV y $EXTRA"
P=$(enviar maitre "maitre_modificar&reservacion_id=$RM" "reservacion_id=$RM" "cantidad=$CANT_RM" "inicio=$INICIO_RM" duracion=100 "mesa_id[]=$MV")
caso "quita una mesa agregada por error, que no es la del pedido" "$(igual "$(sql "SELECT string_agg(mesa_id::TEXT, ',') FROM horarios WHERE reservacion_id = $RM")" "$MV")" "$(mensajes "$P")"
caso "el pedido sigue en su mesa" "$(igual "$(sql "SELECT mesa_id FROM pedidos_detalle WHERE pedido_id = $PED")" "$MV")"

echo "== Tablespaces y particiones (PDF 6.1) =="
for I in 1 2 3; do
    caso "horarios_$I está en ts_reservaciones_$I" "$(igual "$(sql "SELECT t.spcname FROM pg_class c JOIN pg_tablespace t ON t.oid = c.reltablespace WHERE c.relname = 'horarios_$I'")" "ts_reservaciones_$I")"
    caso "horarios_$I tiene datos" "$([ "$(sql "SELECT count(*) FROM horarios_$I")" -gt 0 ] && echo si || echo no)"
done
caso "los tablespaces están en directorios diferentes" "$(igual "$(sql "SELECT count(DISTINCT pg_tablespace_location(t.oid)) FROM pg_class c JOIN pg_tablespace t ON t.oid = c.reltablespace WHERE c.relname IN ('horarios_1', 'horarios_2', 'horarios_3')")" 3)"

echo "== Reportes e historial (PDF 3.6 y 4.3) =="
for per in day week month; do
    P=$(ver admin "admin_reportes&periodo=$per&desde=2026-08-01&hasta=2028-01-01")
    RES=$(sql "SELECT count(*) FROM (SELECT date_trunc('$per', x.i) FROM (SELECT min(h.inicio) AS i FROM horarios h JOIN reservaciones r ON r.id = h.reservacion_id WHERE r.estado <> 3 AND h.inicio >= '2026-08-01' AND h.inicio < '2028-01-01' GROUP BY h.reservacion_id) x GROUP BY 1) y")
    FILAS=$(seccion "$P" 'Reservaciones por periodo' 'Platos más solicitados' | grep -oE '<tr><td>' | wc -l)
    caso "reservaciones por $per: $RES filas" "$(igual "$FILAS" "$RES")"
    VENTA=$(sql "SELECT sum(o.cantidad * p.precio) FROM ordenes o JOIN platos p ON p.id = o.plato_id WHERE o.estado = 2")
    SUMA=$(seccion "$P" 'Ventas entregadas por periodo' | grep -oE '<td>[0-9]+(\.[0-9]+)?</td></tr>' | grep -oE '[0-9]+(\.[0-9]+)?' | awk '{s+=$1} END {printf "%d", s}')
    caso "ventas por $per suman el total $VENTA" "$(igual "$SUMA" "$VENTA")" "suma web: $SUMA"
done
P=$(ver admin "admin_reportes&periodo=month&desde=2026-08-01&hasta=2028-01-01")
TOP=$(sql "SELECT p.nombre FROM ordenes o JOIN platos p ON p.id = o.plato_id GROUP BY p.id, p.nombre ORDER BY sum(o.cantidad) DESC, p.nombre LIMIT 1")
PRIMERO=$(seccion "$P" 'Platos más solicitados' 'Ventas entregadas' | grep -oE '<tr><td>[^<]+' | head -1 | sed 's/<tr><td>//')
caso "el plato más solicitado es $TOP" "$(igual "$PRIMERO" "$TOP")" "web: $PRIMERO"
P=$(ver admin "admin_reportes&periodo=week&desde=2026-08-01&hasta=2028-01-01"); caso "la semana se lee como Semana del" "$(tiene "$P" '<td>Semana del 20')"
P=$(ver admin "admin_reportes&periodo=month&desde=2026-08-01&hasta=2028-01-01"); caso "el mes se lee como AAAA-MM" "$(grep -qE '<td>20[0-9]{2}-[0-9]{2}</td>' <<<"$P" && echo si || echo no)"
P=$(ver admin "admin_reportes&periodo=day&desde=2026-08-01&hasta=2028-01-01"); caso "el día se lee como AAAA-MM-DD" "$(grep -qE '<td>20[0-9]{2}-[0-9]{2}-[0-9]{2}</td>' <<<"$P" && echo si || echo no)"
P=$(ver admin "admin_reportes&desde=2026-13-45&hasta=basura"); caso "fechas inválidas en reportes no rompen la página" "$(tiene "$P" 'Reservaciones por periodo')"
FILAS_WEB() { seccion "$1" "$2" "${3:-}" | sed 's/<tr>/\n<tr>/g' | grep -oE '<tr><td>[^<]+</td><td>[^<]+' | sed -E 's/<tr><td>//; s#</td><td>#=#'; }
for per in day week month; do
    case $per in
        day) FORMATO='YYYY-MM-DD' ;;
        week) FORMATO='"Semana del "YYYY-MM-DD' ;;
        month) FORMATO='YYYY-MM' ;;
    esac
    P=$(ver admin "admin_reportes&periodo=$per&desde=2026-08-01&hasta=2028-01-01")
    ESPERADO=$(sql "SELECT to_char(date_trunc('$per', x.i), '$FORMATO') || '=' || count(*) FROM (SELECT min(h.inicio) AS i FROM horarios h JOIN reservaciones r ON r.id = h.reservacion_id WHERE r.estado <> 3 AND h.inicio >= '2026-08-01' AND h.inicio < '2028-01-01' GROUP BY h.reservacion_id) x GROUP BY date_trunc('$per', x.i) ORDER BY date_trunc('$per', x.i)")
    caso "reservaciones por $per: cada valor coincide con la base" "$(igual "$(FILAS_WEB "$P" 'Reservaciones por periodo' 'Platos más solicitados')" "$ESPERADO")"
    ESPERADO=$(sql "SELECT to_char(date_trunc('$per', o.solicitado AT TIME ZONE 'America/Bogota'), '$FORMATO') || '=' || sum(o.cantidad * p.precio) FROM ordenes o JOIN platos p ON p.id = o.plato_id WHERE o.estado = 2 GROUP BY date_trunc('$per', o.solicitado AT TIME ZONE 'America/Bogota') ORDER BY date_trunc('$per', o.solicitado AT TIME ZONE 'America/Bogota')")
    caso "ventas por $per: cada valor coincide con la base" "$(igual "$(FILAS_WEB "$P" 'Ventas entregadas por periodo')" "$ESPERADO")"
done
ESPERADO=$(sql "SELECT p.nombre || '=' || sum(o.cantidad) FROM ordenes o JOIN platos p ON p.id = o.plato_id GROUP BY p.id, p.nombre ORDER BY sum(o.cantidad) DESC, p.nombre")
caso "platos más solicitados: cada valor coincide con la base" "$(igual "$(FILAS_WEB "$P" 'Platos más solicitados' 'Ventas entregadas')" "$ESPERADO")"
P=$(ver admin "admin_reportes&periodo=hackeo"); caso "periodo inválido no rompe la página" "$(tiene "$P" 'Reservaciones por periodo')"
HC=$(sql "SELECT cliente_id FROM pedidos GROUP BY 1 ORDER BY count(*) DESC LIMIT 1")
P=$(ver admin "admin_historial&cliente_id=$HC")
caso "historial muestra sus reservaciones" "$(igual "$(seccion "$P" '<h2>Reservaciones' 'Pedidos y órdenes' | grep -oE '<tr><td>' | wc -l)" "$(sql "SELECT count(*) FROM reservaciones WHERE cliente_id = $HC")")"
caso "historial muestra sus órdenes" "$(igual "$(seccion "$P" 'Pedidos y órdenes' | grep -oE '<tr><td>' | wc -l)" "$(sql "SELECT count(*) FROM ordenes o JOIN pedidos p ON p.id = o.pedido_id WHERE p.cliente_id = $HC")")"

SIN_MESA=0
for FILA in $(sql "SELECT d.pedido_id || '</td><td>' || d.mesa_id FROM pedidos_detalle d WHERE d.cliente_id = $HC"); do
    [ "$(tiene "$P" "<td>$FILA</td>")" = si ] || SIN_MESA=$((SIN_MESA + 1))
done
caso "historial muestra la mesa de todos sus pedidos" "$(igual "$SIN_MESA" 0)" "$SIN_MESA sin mesa"
TRAMO=$(seccion "$P" '<h2>Reservaciones' 'Pedidos y órdenes')
for PAR in 0:Reservada 1:Ocupada 2:Liberada 3:Cancelada; do
    caso "historial cuenta bien las reservaciones en estado ${PAR#*:}" "$(igual "$(grep -o "<td>${PAR#*:}</td>" <<<"$TRAMO" | wc -l)" "$(sql "SELECT count(*) FROM reservaciones WHERE cliente_id = $HC AND estado = ${PAR%%:*}")")"
done

echo "== Seguridad y salidas =="
ANTES=$(sql "SELECT count(*) FROM mesas"); curl -s -b "$TMP/admin.jar" "$URL?opcion=admin_mesas&accion=agregar&sillas=4" > /dev/null; caso "GET no modifica datos" "$(igual "$(sql "SELECT count(*) FROM mesas")" "$ANTES")"
XSS='<script>alert(1)</script>'
ESCAPADO='&lt;script&gt;alert(1)&lt;/script&gt;'
P=$(enviar admin admin_menu accion=agregar "nombre=$XSS" descripcion=x tipo_id=1 tiempo=5 precio=1)
caso "el plato con etiquetas sí se guardó" "$(igual "$(sql "SELECT count(*) FROM platos WHERE nombre = '$XSS'")" 1)"
P=$(ver admin admin_menu); caso "escapa HTML en administrar menú" "$([ "$(no_tiene "$P" "$XSS")" = si ] && [ "$(tiene "$P" "$ESCAPADO")" = si ] && echo si || echo no)"
P=$(curl -s "$URL?opcion=desplegar_menu"); caso "escapa HTML en el menú público" "$([ "$(no_tiene "$P" "$XSS")" = si ] && [ "$(tiene "$P" "$ESCAPADO")" = si ] && echo si || echo no)"
sql "DELETE FROM platos WHERE nombre = '$XSS'" > /dev/null
P=$(ver admin "admin_historial&cliente_id=1'%20OR%201=1"); caso "ids con texto se leen como número y no traen datos de otros" "$([ "$(tiene "$P" 'Historial del cliente')" = si ] && [ "$(grep -o '<tr><td>' <<<"$P" | wc -l)" = 0 ] && echo si || echo no)"
for pagina in "admin admin_reportes&periodo[]=x&desde[]=x&hasta[]=x" "maitre maitre_reservaciones&dia[]=x" "maitre maitre_disponibilidad&instante[]=x" "maitre maitre_nueva&inicio[]=x"; do
    set -- $pagina
    P=$(ver "$1" "$2"); caso "campos enviados como lista no dan avisos en ${2%%&*}" "$([ "$(tiene "$P" 'Menu del programa')" = si ] && [ "$(sin_avisos "$P")" = si ] && echo si || echo no)"
done
for o in "" desplegar_menu realizar_pedidos iniciar_sesion; do
    P=$(curl -s "$URL?opcion=$o"); caso "sin avisos de PHP en '$o'" "$(sin_avisos "$P")"
done
for par in "admin admin_mesas" "admin admin_menu" "admin admin_empleados" "admin admin_especialidades" "admin admin_reportes" "admin admin_historial" "maitre maitre_reservaciones" "maitre maitre_nueva" "maitre maitre_disponibilidad" "maitre maitre_avisos" "mesero mesero_pedidos" "mesero mesero_avisos" "cocinero cocinero_ordenes"; do
    set -- $par
    P=$(ver "$1" "$2"); caso "sin avisos de PHP en $2" "$(sin_avisos "$P")"
done
for par in "admin admin_historial&cliente_id=$HC" "maitre maitre_reservaciones" "mesero mesero_pedidos" "cocinero cocinero_ordenes"; do
    set -- $par
    P=$(ver "$1" "$2"); caso "fechas sin segundos en ${2%%&*}" "$(grep -qE '[0-9]{2}:[0-9]{2}:[0-9]{2}' <<<"$P" && echo no || echo si)"
done
caso "ninguna página visitada en estas pruebas mostró avisos de PHP" "$(grep -qE "$AVISOS_PHP" "$TMP/visitadas.html" && echo no || echo si)"
P=$(curl -g -s "$URL?opcion[]=x"); caso "control: el detector sí reconoce un aviso de PHP" "$([ "$(sin_avisos "$P")" = no ] && echo si || echo no)"
JS=$(curl -s "${URL}lib/programa.js"); caso "se publica el script que actualiza los avisos" "$(tiene "$JS" 'setInterval')"
for f in .aider.chat.history.md .aider.input.history sql/05_datos.sql docs/decisiones.md AGENTS.md; do
    C=$(curl -s -o /dev/null -w '%{http_code}' "$URL$f"); caso "no se publica $f" "$(igual "$C" 404)" "código $C"
done
P=$(enviar admin cerrar_sesion enviar=1); P=$(ver admin admin_mesas); caso "cerrar sesión termina el acceso" "$(tiene "$P" 'Se requiere iniciar sesión')"

rm -rf "$TMP"
psql -w -X -q -d "$BASE" -f sql/05_datos.sql > /dev/null 2>&1
echo "Total: $TOTAL casos, $FALLIDOS fallidos"
exit "$FALLIDOS"
