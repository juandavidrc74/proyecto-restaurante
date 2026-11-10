# Proyecto Restaurante

Aplicación PHP y base de datos PostgreSQL para gestionar las mesas, las reservaciones, el menú, los pedidos y las entregas de un restaurante. Bases de datos: Administración y Aplicaciones, Pontificia Universidad Javeriana.

## Documentación

| Documento | Contenido |
|---|---|
| [docs/documentacion.md](docs/documentacion.md) | Diseño, diagrama, diccionario de datos, tablespaces, particiones, casos de uso, consultas e instrucciones |
| [docs/decisiones.md](docs/decisiones.md) | Decisiones de diseño e interpretaciones del enunciado |
| [docs/resultados_pruebas.md](docs/resultados_pruebas.md) | Caso, resultado esperado, resultado obtenido y estado de cada prueba |
| [docs/auditoria_final.md](docs/auditoria_final.md) | Matriz de trazabilidad y auditoría de lo que no se pidió |

## Orden de los scripts

1. `sql/00_preparacion_administrador.sql`: una sola vez, con un administrador de PostgreSQL.
2. `sql/reconstruir.sql`: ejecuta `01_estructura`, `02_restricciones`, `03_tablespaces_particiones` y `04_funciones_triggers`. **Borra el esquema de `restaurante_proyecto`.**
3. `sql/05_datos.sql`: datos de prueba. Vuelva a cargarlo antes de una demostración.
4. `sql/06_consultas.sql`: consultas de cada caso de uso. No cambia datos.

Las instrucciones completas están en la [sección 10 de la documentación](docs/documentacion.md#10-instrucciones-de-ejecución).
