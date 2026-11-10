-- Lista lo que existe en el catálogo de PostgreSQL, para comparar la documentación con la base real.
-- Ejecutar conectado a restaurante_proyecto con psql. No cambia datos.

\echo === Columnas
SELECT c.table_name,
       c.column_name,
       c.data_type,
       c.is_nullable,
       COALESCE(c.column_default, '') AS por_omision
  FROM information_schema.columns c
  JOIN pg_class k ON k.relname = c.table_name
 WHERE c.table_schema = 'public'
   AND k.relkind IN ('r', 'p')
   AND NOT k.relispartition
 ORDER BY c.table_name, c.ordinal_position;

\echo === Restricciones
SELECT conrelid::regclass AS tabla,
       conname AS restriccion,
       contype AS tipo,
       pg_get_constraintdef(oid) AS definicion
  FROM pg_constraint
 WHERE connamespace = 'public'::regnamespace
   AND conrelid <> 0
   AND conparentid = 0
 ORDER BY conrelid::regclass::TEXT, contype, conname;

\echo === Indices
SELECT tablename AS tabla,
       indexname AS indice
  FROM pg_indexes
 WHERE schemaname = 'public'
   AND tablename NOT LIKE 'horarios\_%'
 ORDER BY tablename, indexname;

\echo === Triggers
SELECT c.relname AS tabla,
       t.tgname AS trigger_nombre,
       CASE WHEN t.tgdeferrable THEN 'diferido' ELSE 'inmediato' END AS momento,
       p.proname AS funcion
  FROM pg_trigger t
  JOIN pg_class c ON c.oid = t.tgrelid
  JOIN pg_proc p ON p.oid = t.tgfoid
 WHERE NOT t.tgisinternal
   AND t.tgparentid = 0
 ORDER BY c.relname, t.tgname;

\echo === Funciones
SELECT proname || '(' || pg_get_function_identity_arguments(oid) || ')' AS funcion,
       CASE provolatile WHEN 'v' THEN 'VOLATILE' WHEN 's' THEN 'STABLE' ELSE 'IMMUTABLE' END AS volatilidad
  FROM pg_proc
 WHERE pronamespace = 'public'::regnamespace
 ORDER BY 1;

\echo === Vistas
SELECT viewname AS vista
  FROM pg_views
 WHERE schemaname = 'public';

\echo === Tablespaces
SELECT spcname AS tablespace,
       pg_tablespace_location(oid) AS directorio
  FROM pg_tablespace
 WHERE spcname LIKE 'ts_reservaciones_%'
 ORDER BY spcname;

\echo === Particiones
SELECT c.relname AS particion,
       pg_get_expr(c.relpartbound, c.oid) AS rango,
       t.spcname AS tablespace
  FROM pg_class c
  JOIN pg_tablespace t ON t.oid = c.reltablespace
 WHERE c.relispartition
   AND c.relkind = 'r'
 ORDER BY c.relname;
