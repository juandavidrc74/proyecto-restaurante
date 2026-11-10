#!/bin/bash
# Pruebas con sesiones realmente simultáneas y prueba de volumen.
# ATENCIÓN: borra los datos de restaurante_proyecto. Al terminar reconstruye la
# base y, si existe, carga sql/05_datos.sql.
# Uso, desde la carpeta del proyecto: bash pruebas/02_concurrencia_volumen.sh --confirmar-borrado
set -uo pipefail

if [ "${1:-}" != "--confirmar-borrado" ]; then
    echo "Este script borra los datos de restaurante_proyecto. Use --confirmar-borrado."
    exit 2
fi

BASE=restaurante_proyecto
P="psql -w -X -q -At -v VERBOSITY=terse -d $BASE"
TMP=$(mktemp -d)
FALLIDOS=0

verificar() { # caso esperado obtenido
    if [ "$2" = "$3" ]; then
        echo "APROBADO | $1 | $3"
    else
        echo "FALLIDO  | $1 | esperado: $2 | obtenido: $3"
        FALLIDOS=$((FALLIDOS + 1))
    fi
}

limpiar() {
$P <<'SQL'
SET client_min_messages = warning;
TRUNCATE roles, tipos, usuarios, mesas, reservaciones, platos, actuaciones, especialidades, pedidos, ordenes, preparaciones, horarios RESTART IDENTITY CASCADE;
INSERT INTO usuarios (id, nombre) VALUES (1,'Cliente A'),(2,'Cliente B');
INSERT INTO mesas (id, sillas) VALUES (1,4),(2,4);
SQL
}

reserva() { # id cliente cantidad mesa espera
cat <<SQL
BEGIN;
INSERT INTO reservaciones (id, cliente_id, cantidad) VALUES ($1,$2,$3);
INSERT INTO horarios (mesa_id, reservacion_id, inicio, duracion) VALUES ($4,$1,'2026-12-01 12:00','1 hour');
SELECT pg_sleep($5);
COMMIT;
SQL
}

error_de() { grep -m1 -oE 'ERROR: .*' "$1" | sed -E 's/^ERROR: +//; s/ [0-9]+ / N /g' || true; }

# 1. Misma mesa y hora: la segunda sesión espera el bloqueo y es rechazada.
limpiar
reserva 1 1 2 1 3 | $P > "$TMP/a.txt" 2>&1 &
sleep 1
inicio=$(date +%s%N)
reserva 2 2 2 1 0 | $P > "$TMP/b.txt" 2>&1
fin=$(date +%s%N)
wait
espera=$(( (fin - inicio) / 1000000 ))
verificar "cruce: la primera sesión confirma" "" "$(error_de "$TMP/a.txt")"
verificar "cruce: la segunda sesión es rechazada" "La mesa N ya tiene una reservación activa en ese horario." "$(error_de "$TMP/b.txt")"
verificar "cruce: la segunda sesión esperó el bloqueo" "si" "$([ "$espera" -ge 1000 ] && echo si || echo no)"
verificar "cruce: queda una reservación" "1" "$($P -c 'SELECT count(*) FROM reservaciones')"

# 2. Cupo: dos sesiones que caben por separado y juntas lo superan. Cupo total 8.
limpiar
reserva 1 1 4 1 3 | $P > "$TMP/a.txt" 2>&1 &
sleep 1
reserva 2 2 6 2 0 | $P > "$TMP/b.txt" 2>&1
wait
# La primera pide 4 y confirma. La segunda pide 6 en otra mesa: tras esperar el
# bloqueo debe ver lo confirmado por la primera y caer por cupo (4 + 6 > 8).
# Si no esperara o no viera ese dato, no fallaría por cupo.
verificar "cupo: la primera sesión confirma" "" "$(error_de "$TMP/a.txt")"
verificar "cupo: la segunda sesión es rechazada por cupo" "si" "$(grep -q 'cupo del restaurante se supera' "$TMP/b.txt" && echo si || echo no)"
verificar "cupo: queda una reservación" "1" "$($P -c 'SELECT count(*) FROM reservaciones')"

# 3. Reducir sillas mientras otra sesión reserva esa mesa.
limpiar
reserva 1 1 4 1 3 | $P > "$TMP/a.txt" 2>&1 &
sleep 1
$P -c "UPDATE mesas SET sillas = 2 WHERE id = 1;" > "$TMP/b.txt" 2>&1
wait
verificar "sillas: la reservación confirma" "" "$(error_de "$TMP/a.txt")"
verificar "sillas: la reducción es rechazada" "4" "$($P -c 'SELECT sillas FROM mesas WHERE id = 1')"

# 4. Orden nueva mientras otra sesión cancela la reservación.
limpiar
$P <<'SQL'
INSERT INTO roles (id, nombre) VALUES (3,'mesero');
INSERT INTO tipos (id, nombre) VALUES (1,'entrada');
INSERT INTO usuarios (id, nombre) VALUES (3,'Mesero');
INSERT INTO actuaciones (usuario_id, rol_id) VALUES (3,3);
INSERT INTO platos (id, tipo_id, nombre, descripcion, tiempo, precio) VALUES (1,1,'P','d','10 min',1);
BEGIN;
INSERT INTO reservaciones (id, cliente_id, cantidad) VALUES (1,1,2);
INSERT INTO horarios (mesa_id, reservacion_id, inicio, duracion) VALUES (1,1,'2026-12-01 12:00','1 hour');
COMMIT;
INSERT INTO pedidos (id, cliente_id, mesero_id) VALUES (1,1,3);
SQL
cat <<'SQL' | $P > "$TMP/a.txt" 2>&1 &
BEGIN;
UPDATE reservaciones SET estado = 3 WHERE id = 1;
SELECT pg_sleep(3);
COMMIT;
SQL
sleep 1
$P -c "INSERT INTO ordenes (plato_id, pedido_id, cantidad, solicitado) VALUES (1,1,1,'2026-12-01 12:30-05');" > "$TMP/b.txt" 2>&1
wait
verificar "carrera: la orden es rechazada tras la cancelación" "0" "$($P -c 'SELECT count(*) FROM ordenes')"

# 5. Volumen: 1400 reservaciones activas por las reglas reales.
limpiar
$P <<'SQL'
SET client_min_messages = warning;
TRUNCATE mesas, usuarios CASCADE;
INSERT INTO usuarios (id, nombre) VALUES (1,'Cliente');
INSERT INTO mesas (id, sillas) SELECT g, 4 FROM generate_series(1,20) g;
SQL
inicio=$(date +%s%N)
$P > "$TMP/vol.txt" 2>&1 <<'SQL'
SET statement_timeout = '120s';
DO $$
DECLARE i int; r int;
BEGIN
  FOR i IN 1..1400 LOOP
    INSERT INTO reservaciones (cliente_id, cantidad) VALUES (1,2) RETURNING id INTO r;
    INSERT INTO horarios (mesa_id, reservacion_id, inicio, duracion)
    VALUES (1 + (i % 20), r, timestamp '2030-01-01 12:00' + (i || ' days')::interval, '1 hour');
  END LOOP;
END $$;
SQL
fin=$(date +%s%N)
verificar "volumen: 1400 reservaciones sin error" "" "$(error_de "$TMP/vol.txt")"
echo "Tiempo de 1400 reservaciones: $(( (fin - inicio) / 1000000 )) ms"
verificar "volumen: menos de 30 s" "si" "$([ $(( (fin - inicio) / 1000000 )) -lt 30000 ] && echo si || echo no)"

rm -rf "$TMP"

# Dejar la base como estaba: estructura y, si existen, datos de prueba.
psql -w -X -q -d "$BASE" -f sql/reconstruir.sql > /dev/null 2>&1
[ -f sql/05_datos.sql ] && psql -w -X -q -d "$BASE" -f sql/05_datos.sql > /dev/null 2>&1

echo "Total fallidos: $FALLIDOS"
exit "$FALLIDOS"
