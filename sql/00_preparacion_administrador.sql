-- Ejecutar una sola vez con un rol administrador de PostgreSQL.

-- En la máquina virtual estos tablespaces ya existen y no deben volver a crearse.
-- En un servidor nuevo: crear los directorios con dueño postgres y quitar estos comentarios.
-- CREATE TABLESPACE ts_reservaciones_1 LOCATION '/var/lib/pgsql/tablespaces/reservaciones_1';
-- CREATE TABLESPACE ts_reservaciones_2 LOCATION '/var/lib/pgsql/tablespaces/reservaciones_2';
-- CREATE TABLESPACE ts_reservaciones_3 LOCATION '/var/lib/pgsql/tablespaces/reservaciones_3';

CREATE DATABASE restaurante_proyecto OWNER estudiante;
\connect restaurante_proyecto
ALTER SCHEMA public OWNER TO estudiante;
GRANT CREATE ON TABLESPACE ts_reservaciones_1 TO estudiante;
GRANT CREATE ON TABLESPACE ts_reservaciones_2 TO estudiante;
GRANT CREATE ON TABLESPACE ts_reservaciones_3 TO estudiante;
