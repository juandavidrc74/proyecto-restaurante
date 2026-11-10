\set ON_ERROR_STOP on

SELECT current_database() = 'restaurante_proyecto' AS base_correcta \gset
\if :base_correcta
    BEGIN;
    DROP SCHEMA public CASCADE;
    CREATE SCHEMA public;
    \ir 01_estructura.sql
    \ir 02_restricciones.sql
    \ir 03_tablespaces_particiones.sql
    \ir 04_funciones_triggers.sql
    COMMIT;
\else
    \echo 'ERROR: reconstructor detenido; la base actual no es restaurante_proyecto.'
    \quit 3
\endif

-- Los datos se cargan aparte con sql/05_datos.sql.
