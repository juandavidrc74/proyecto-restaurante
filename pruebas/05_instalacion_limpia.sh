#!/bin/bash
# Prueba la instalación en un servidor nuevo: sql/00, reconstruir, sql/05 y sql/06.
# Usa un clúster temporal que solo escucha en un socket privado y se borra al terminar.
# No toca el clúster del sistema ni la base restaurante_proyecto real.
# Uso, desde la carpeta del proyecto en la VM: bash pruebas/05_instalacion_limpia.sh
set -u
if [ ! -f sql/reconstruir.sql ]; then
    echo "Ejecute este script desde la carpeta del proyecto."
    exit 1
fi

T=$(mktemp -d /tmp/prueba_instalacion.XXXXXX) || exit 1
limpiar() {
    pg_ctl -D "$T/data" -m fast -w stop > /dev/null 2>&1
    rm -rf -- "$T"
}
trap limpiar EXIT

initdb -D "$T/data" -U "$(id -un)" --auth=trust -E UTF8 --locale=en_US.UTF-8 > "$T/initdb.log" 2>&1 \
    || { echo "FALLA initdb"; tail -5 "$T/initdb.log"; exit 1; }
pg_ctl -D "$T/data" -w -l "$T/server.log" \
    -o "-p 55433 -c listen_addresses='' -c unix_socket_directories=$T" start > /dev/null \
    || { echo "FALLA arranque"; tail -5 "$T/server.log"; exit 1; }

export PGHOST="$T" PGPORT=55433
unset PGDATABASE PGSERVICE PGUSER

# Nada se ejecuta si la conexión no llega al clúster temporal.
DATOS=$(psql -w -X -At -d postgres -c "SHOW data_directory")
if [ "$DATOS" != "$T/data" ]; then
    echo "ABORTADO: la conexión no llegó al clúster temporal."
    exit 2
fi
echo "Clúster temporal de PostgreSQL $(psql -w -X -At -d postgres -c 'SHOW server_version')"

# sql/00 como indica su comentario para un servidor nuevo; solo cambian las rutas de los directorios.
mkdir "$T/ts1" "$T/ts2" "$T/ts3"
sed -e 's/^-- CREATE TABLESPACE/CREATE TABLESPACE/' \
    -e "s#/var/lib/pgsql/tablespaces/reservaciones_#$T/ts#" \
    sql/00_preparacion_administrador.sql > "$T/00.sql"

paso() {
    NOMBRE=$1; shift
    if "$@" > "$T/salida_$NOMBRE.txt" 2>&1; then
        echo "APROBADO | $NOMBRE"
    else
        echo "FALLIDO  | $NOMBRE (código $?)"
        grep -E "ERROR|FATAL" "$T/salida_$NOMBRE.txt" | head -5
        exit 3
    fi
}

huella() {
    for TABLA in tipos platos usuarios roles actuaciones especialidades mesas reservaciones horarios pedidos ordenes preparaciones; do
        echo "$TABLA $(psql -w -X -At -d restaurante_proyecto -c "SELECT count(*), md5(string_agg(x::text, ',' ORDER BY x::text)) FROM $TABLA x")"
    done
}

paso 00_preparacion psql -w -X -v ON_ERROR_STOP=1 -d postgres -f "$T/00.sql"
paso reconstruir psql -w -X -v ON_ERROR_STOP=1 -d restaurante_proyecto -f sql/reconstruir.sql
paso 05_datos psql -w -X -v ON_ERROR_STOP=1 -d restaurante_proyecto -f sql/05_datos.sql
huella > "$T/antes.txt"
paso 06_consultas psql -w -X -q -v ON_ERROR_STOP=1 -d restaurante_proyecto -f sql/06_consultas.sql
huella > "$T/despues.txt"

if diff -q "$T/antes.txt" "$T/despues.txt" > /dev/null; then
    echo "APROBADO | sql/06 no cambia los datos de las 12 tablas"
else
    echo "FALLIDO  | sql/06 cambió datos"
    diff "$T/antes.txt" "$T/despues.txt" | cut -d' ' -f1-3
fi

VACIAS=$(grep -c -E "^\(0 rows\)" "$T/salida_06_consultas.txt")
if [ "$VACIAS" = "0" ]; then
    echo "APROBADO | ninguna consulta de sql/06 sale vacía con los datos recién cargados"
else
    echo "FALLIDO  | $VACIAS consultas de sql/06 salen vacías"
    grep -n -B4 -E "^\(0 rows\)" "$T/salida_06_consultas.txt" | head -20
fi

echo "Filas cargadas:"
cut -d'|' -f1 "$T/antes.txt"
echo "Particiones y tablespaces:"
psql -w -X -At -F ' ' -d restaurante_proyecto -c "
    SELECT c.relname, t.spcname
      FROM pg_inherits i
      JOIN pg_class c ON c.oid = i.inhrelid
      JOIN pg_tablespace t ON t.oid = c.reltablespace
     WHERE i.inhparent = 'horarios'::regclass
     ORDER BY 1"

cp "$T/salida_06_consultas.txt" pruebas/resultados/06_consultas.txt
