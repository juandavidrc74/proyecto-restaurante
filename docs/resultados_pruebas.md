# Resultados de las pruebas

Generado a partir de las salidas reales de `pruebas/resultados/`, de la ejecución del 2026-11-06 en la máquina virtual. Ningún caso se escribió a mano.

## Resumen

| Batería | Qué comprueba | Casos | Fallidos |
|---|---|---|---|
| `pruebas/01_integridad.sql` | Restricciones, triggers y reglas directamente en la base | 72 | 0 |
| `pruebas/02_concurrencia_volumen.sh` | Sesiones simultáneas reales y volumen | 12 | 0 |
| `pruebas/03_aplicacion.sh` | La aplicación por HTTP, con la sesión real de cada rol | 244 | 0 |
| **Total** | | **328** | **0** |

`sql/06_consultas.sql` se ejecutó completo, con `ON_ERROR_STOP`, sin errores. Su salida está en `pruebas/resultados/06_consultas.txt`.

`pruebas/05_instalacion_limpia.sh` probó el 2026-11-08 la instalación en un servidor nuevo, en un clúster temporal con los tablespaces en directorios temporales. Estos casos no se cuentan en el total anterior. Su salida está en `pruebas/resultados/05_instalacion_limpia.txt`.

| Caso | Resultado esperado | Resultado obtenido | Estado |
|---|---|---|---|
| `sql/00`, con sus `CREATE TABLESPACE` | Crea los tablespaces y la base | Sin errores | APROBADO |
| `sql/reconstruir.sql` | Crea el esquema | Sin errores | APROBADO |
| `sql/05_datos.sql` | Carga los datos de prueba | Sin errores | APROBADO |
| `sql/06_consultas.sql` | Corre completo | Sin errores | APROBADO |
| `sql/06` no cambia los datos | Las 12 tablas quedan iguales | Misma cantidad y misma huella `md5` | APROBADO |
| Consultas de `sql/06` con los datos recién cargados | Ninguna sale vacía | 0 vacías | APROBADO |

Además se recorrieron los cuatro roles en un navegador real sobre la versión final: botones del menú, reportes, modificación de una reservación agregándole una mesa, registro de un pedido desde la pantalla de la mesa, Marcar listo y entrega de una orden. La orden que otra sesión marcó lista apareció en el aviso del mesero, con su botón, sin recargar la página y en menos de 30 segundos, y ese botón funcionó. La reservación que otra sesión creó apareció igual en el aviso del maitre. El formulario de inicio de sesión se probó en el navegador en una versión anterior; su código no cambió, salvo la lectura de la clave, y la batería 03 lo cubre. Este recorrido se hizo a mano y no forma parte de las baterías.

En las baterías 02 y 03, el nombre del caso es el resultado esperado. "Se cumple" indica que la comprobación automática dio el valor esperado; cuando la prueba guarda un valor o mensaje, se muestra.

## 1. Integridad de la base de datos

| Caso | Resultado esperado | Resultado obtenido | Estado |
|---|---|---|---|
| actuación usuario-rol única | RECHAZO | RECHAZO: duplicate key value violates unique constraint "uq_actuaciones_usuario_rol" | APROBADO |
| borrar orden solicitada sin preparaciones | ÉXITO | ÉXITO | APROBADO |
| borrar y reponer horario con pedidos se rechaza | RECHAZO | RECHAZO: No se puede quitar ni mover este horario: tiene pedidos asociados. | APROBADO |
| cambiar cantidad revalida las sillas | RECHAZO | RECHAZO: La reservación 910024 requiere 9 sillas a las 2026-11-10 10:00:00, pero sus mesas asignadas solo ofrecen 4. | APROBADO |
| cambiar cliente de reservación con pedidos se rechaza | RECHAZO | RECHAZO: No se puede cambiar el cliente: la reservación tiene horarios con pedidos asociados. | APROBADO |
| cambiar cliente de reservación sin pedidos se permite | ÉXITO | ÉXITO | APROBADO |
| cambiar duración de horario con pedidos se permite | ÉXITO | ÉXITO | APROBADO |
| cambiar inicio de horario con pedidos se rechaza | RECHAZO | RECHAZO: No se puede cambiar inicio, mesa o reservación del horario: tiene pedidos asociados. | APROBADO |
| cambiar mesa de horario con pedidos se rechaza | RECHAZO | RECHAZO: No se puede cambiar inicio, mesa o reservación del horario: tiene pedidos asociados. | APROBADO |
| cambiar plato y cantidad de orden solicitada | ÉXITO | ÉXITO | APROBADO |
| cambiar reservación de horario con pedidos se rechaza | RECHAZO | RECHAZO: No se puede cambiar inicio, mesa o reservación del horario: tiene pedidos asociados. | APROBADO |
| cancelar reservación con pedidos se rechaza | RECHAZO | RECHAZO: No se puede cancelar la reservación: uno de sus horarios tiene pedidos asociados. | APROBADO |
| cancelar reservación sin pedidos se permite | ÉXITO | ÉXITO | APROBADO |
| cantidad de orden positiva | RECHAZO | RECHAZO: new row for relation "ordenes" violates check constraint "ck_ordenes_cantidad_positiva" | APROBADO |
| cantidad de reservación positiva | RECHAZO | RECHAZO: new row for relation "reservaciones" violates check constraint "ck_reservaciones_cantidad_positiva" | APROBADO |
| categoría de tipo limitada | RECHAZO | RECHAZO: new row for relation "tipos" violates check constraint "ck_tipos_categoria" | APROBADO |
| clave y fecha_clave juntas | RECHAZO | RECHAZO: new row for relation "usuarios" violates check constraint "ck_usuarios_clave_fecha_juntas" | APROBADO |
| cocinero especializado prepara orden solicitada | ÉXITO | ÉXITO | APROBADO |
| cruce con reservación cancelada permitido | ÉXITO | ÉXITO | APROBADO |
| cruce en la misma mesa se rechaza | RECHAZO | RECHAZO: La mesa 910001 ya tiene una reservación activa en ese horario. | APROBADO |
| dos mesas de una reservación se cuentan una vez | ÉXITO | ÉXITO | APROBADO |
| duración 1:59 se permite | ÉXITO | ÉXITO | APROBADO |
| duración cero se rechaza | RECHAZO | RECHAZO: new row for relation "horarios_2" violates check constraint "ck_horarios_duracion" | APROBADO |
| duración de dos horas se rechaza | RECHAZO | RECHAZO: new row for relation "horarios_2" violates check constraint "ck_horarios_duracion" | APROBADO |
| duración negativa se rechaza | RECHAZO | RECHAZO: new row for relation "horarios_2" violates check constraint "ck_horarios_duracion" | APROBADO |
| eliminar cocinero con especialidades se permite | ÉXITO | ÉXITO | APROBADO |
| especialidad exige rol cocinero | RECHAZO | RECHAZO: El usuario 910001 debe tener el rol de cocinero para registrar especialidades. | APROBADO |
| estado de reservación dentro del rango | RECHAZO | RECHAZO: Una reservación nueva debe iniciar en estado reservada (0). | APROBADO |
| estado final cancelada no admite transición | RECHAZO | RECHAZO: No se puede modificar una reservación liberada o cancelada. | APROBADO |
| estado final liberada no admite transición | RECHAZO | RECHAZO: No se puede modificar una reservación liberada o cancelada. | APROBADO |
| horarios propios cruzados en misma mesa se rechazan | RECHAZO | RECHAZO: La mesa 910001 ya tiene una reservación activa en ese horario. | APROBADO |
| identificador de mesa único | RECHAZO | RECHAZO: duplicate key value violates unique constraint "mesas_pkey" | APROBADO |
| id repetido entre particiones se rechaza | RECHAZO | RECHAZO: El identificador de horario 991015 ya está en uso. | APROBADO |
| liberar con pedidos conserva mesa derivada | ÉXITO | ÉXITO | APROBADO |
| mesa de pedido con dos mesas devuelve la menor | ÉXITO | ÉXITO | APROBADO |
| mesas con sillas positivas | RECHAZO | RECHAZO: new row for relation "mesas" violates check constraint "ck_mesas_sillas_positivas" | APROBADO |
| mover horario entre particiones válido | ÉXITO | ÉXITO | APROBADO |
| mover horario que crea cruce se rechaza | RECHAZO | RECHAZO: La mesa 910001 ya tiene una reservación activa en ese horario. | APROBADO |
| no agregar horario a liberada | RECHAZO | RECHAZO: No se puede agregar un horario a una reservación liberada o cancelada. | APROBADO |
| no borrar horario de reservación cancelada | RECHAZO | RECHAZO: No se puede cambiar ni borrar el horario de una reservación liberada o cancelada. | APROBADO |
| no borrar orden preparada | RECHAZO | RECHAZO: Solo se puede borrar una orden solicitada y sin preparaciones. | APROBADO |
| no borrar preparación de orden preparada | RECHAZO | RECHAZO: No se puede cambiar ni borrar la preparación: la orden ya está preparada o entregada. | APROBADO |
| no cambiar cantidad de orden preparada | RECHAZO | RECHAZO: Solo se puede cambiar el plato o la cantidad de una orden solicitada y sin preparaciones. | APROBADO |
| no cambiar cantidad de reservación liberada | RECHAZO | RECHAZO: No se puede modificar una reservación liberada o cancelada. | APROBADO |
| no cambiar horario final | RECHAZO | RECHAZO: No se puede cambiar ni borrar el horario de una reservación liberada o cancelada. | APROBADO |
| no insertar reservación cancelada | RECHAZO | RECHAZO: Una reservación nueva debe iniciar en estado reservada (0). | APROBADO |
| nombre de plato único | RECHAZO | RECHAZO: duplicate key value violates unique constraint "uq_platos_nombre" | APROBADO |
| nombre de rol único | RECHAZO | RECHAZO: duplicate key value violates unique constraint "uq_roles_nombre" | APROBADO |
| nombre de tipo único | RECHAZO | RECHAZO: duplicate key value violates unique constraint "uq_tipos_nombre" | APROBADO |
| no sumar mesas de horarios en horas distintas | RECHAZO | RECHAZO: La reservación 911040 requiere 6 sillas a las 2026-11-11 12:00:00, pero sus mesas asignadas solo ofrecen 4. | APROBADO |
| orden no cambia pedido_id | RECHAZO | RECHAZO: No se puede cambiar la fecha solicitada ni el pedido de una orden. | APROBADO |
| orden no cambia solicitado | RECHAZO | RECHAZO: No se puede cambiar la fecha solicitada ni el pedido de una orden. | APROBADO |
| orden no pasa a preparada sin preparación | RECHAZO | RECHAZO: La orden necesita al menos una preparación antes de marcarse preparada. | APROBADO |
| orden sin reservación vigente se rechaza | RECHAZO | RECHAZO: El cliente del pedido no tiene una reservación vigente a la hora solicitada. | APROBADO |
| pedido no cambia cliente con órdenes | RECHAZO | RECHAZO: No se puede cambiar el cliente del pedido porque ya tiene órdenes. | APROBADO |
| pedido requiere rol de mesero | RECHAZO | RECHAZO: El usuario 910001 debe tener el rol de mesero para registrar el pedido. | APROBADO |
| precio de plato no negativo | RECHAZO | RECHAZO: new row for relation "platos" violates check constraint "ck_platos_precio_valido" | APROBADO |
| precio de plato no puede ser NaN | RECHAZO | RECHAZO: new row for relation "platos" violates check constraint "ck_platos_precio_valido" | APROBADO |
| preparaciones restringen eliminar cocinero | RECHAZO | RECHAZO: update or delete on table "usuarios" violates foreign key constraint "fk_preparaciones_cocinero" on table "preparaciones" | APROBADO |
| preparación requiere especialidad del plato | RECHAZO | RECHAZO: El cocinero 910002 no tiene especialidad para el plato 910001. | APROBADO |
| quitar rol de cocinero con historial se rechaza | RECHAZO | RECHAZO: No se puede quitar el rol de cocinero: el usuario tiene especialidades o preparaciones registradas. | APROBADO |
| quitar rol directamente con especialidad se rechaza | RECHAZO | RECHAZO: No se puede quitar el rol de cocinero: el usuario tiene especialidades o preparaciones registradas. | APROBADO |
| reducir sillas con asignación se rechaza | RECHAZO | RECHAZO: La reservación 910015 requiere 4 sillas a las 2026-10-21 00:00:00, pero sus mesas asignadas solo ofrecen 3. | APROBADO |
| retroceso de estado de orden se rechaza | RECHAZO | RECHAZO: Transición de orden no permitida: 1 a 0. | APROBADO |
| salto de estado de orden se rechaza | RECHAZO | RECHAZO: Transición de orden no permitida: 0 a 2. | APROBADO |
| sillas insuficientes se rechazan diferido | RECHAZO | RECHAZO: La reservación 910008 requiere 5 sillas a las 2026-11-10 10:00:00, pero sus mesas asignadas solo ofrecen 4. | APROBADO |
| sillas suficientes en cada horario distinto | ÉXITO | ÉXITO | APROBADO |
| superar cupo se rechaza | RECHAZO | RECHAZO: El cupo del restaurante se supera a las 2026-11-10 10:00:00; ajuste las reservaciones o las mesas. | APROBADO |
| tiempo de plato positivo | RECHAZO | RECHAZO: new row for relation "platos" violates check constraint "ck_platos_tiempo_positivo" | APROBADO |
| transición reservada a ocupada permitida | ÉXITO | ÉXITO | APROBADO |
| usuario nombre no vacío | RECHAZO | RECHAZO: new row for relation "usuarios" violates check constraint "ck_usuarios_nombre_no_vacio" | APROBADO |
| ventanas contiguas permitidas | ÉXITO | ÉXITO | APROBADO |

## 2. Concurrencia y volumen

| Caso | Resultado esperado | Resultado obtenido | Estado |
|---|---|---|---|
| cruce: la primera sesión confirma | Lo que dice el caso | Se cumple | APROBADO |
| cruce: la segunda sesión es rechazada | Lo que dice el caso | La mesa N ya tiene una reservación activa en ese horario. | APROBADO |
| cruce: la segunda sesión esperó el bloqueo | Lo que dice el caso | si | APROBADO |
| cruce: queda una reservación | Lo que dice el caso | 1 | APROBADO |
| cupo: la primera sesión confirma | Lo que dice el caso | Se cumple | APROBADO |
| cupo: la segunda sesión es rechazada por cupo | Lo que dice el caso | si | APROBADO |
| cupo: queda una reservación | Lo que dice el caso | 1 | APROBADO |
| sillas: la reservación confirma | Lo que dice el caso | Se cumple | APROBADO |
| sillas: la reducción es rechazada | Lo que dice el caso | 4 | APROBADO |
| carrera: la orden es rechazada tras la cancelación | Lo que dice el caso | 0 | APROBADO |
| volumen: 1400 reservaciones sin error | Lo que dice el caso | Se cumple | APROBADO |
| volumen: menos de 30 s | Lo que dice el caso | si | APROBADO |

## 3. Aplicación por rol

| Caso | Resultado esperado | Resultado obtenido | Estado |
|---|---|---|---|
| menú público conserva Desplegar Menu y Realizar Pedido | Lo que dice el caso | se cumple | APROBADO |
| Desplegar Menu muestra los 24 platos | Lo que dice el caso | se cumple | APROBADO |
| sin sesión se rechaza admin_mesas | Lo que dice el caso | se cumple | APROBADO |
| sin sesión se rechaza admin_menu | Lo que dice el caso | se cumple | APROBADO |
| sin sesión se rechaza admin_empleados | Lo que dice el caso | se cumple | APROBADO |
| sin sesión se rechaza admin_especialidades | Lo que dice el caso | se cumple | APROBADO |
| sin sesión se rechaza admin_reportes | Lo que dice el caso | se cumple | APROBADO |
| sin sesión se rechaza admin_historial | Lo que dice el caso | se cumple | APROBADO |
| sin sesión se rechaza maitre_reservaciones | Lo que dice el caso | se cumple | APROBADO |
| sin sesión se rechaza maitre_nueva | Lo que dice el caso | se cumple | APROBADO |
| sin sesión se rechaza maitre_disponibilidad | Lo que dice el caso | se cumple | APROBADO |
| sin sesión se rechaza maitre_modificar | Lo que dice el caso | se cumple | APROBADO |
| sin sesión se rechaza maitre_avisos | Lo que dice el caso | se cumple | APROBADO |
| sin sesión se rechaza mesero_pedidos | Lo que dice el caso | se cumple | APROBADO |
| sin sesión se rechaza mesero_avisos | Lo que dice el caso | se cumple | APROBADO |
| sin sesión se rechaza cocinero_ordenes | Lo que dice el caso | se cumple | APROBADO |
| clave incorrecta rechazada | Lo que dice el caso | se cumple | APROBADO |
| tras clave incorrecta no hay sesión | Lo que dice el caso | se cumple | APROBADO |
| un cliente no puede iniciar sesión | Lo que dice el caso | se cumple | APROBADO |
| al iniciar sesión muestra el menú | Lo que dice el caso | se cumple | APROBADO |
| administrador ve sus accesos | Lo que dice el caso | se cumple | APROBADO |
| administrador no ve accesos de cocinero | Lo que dice el caso | se cumple | APROBADO |
| cocinero no ve accesos de administrador | Lo que dice el caso | se cumple | APROBADO |
| maitre no accede a admin_mesas | Lo que dice el caso | se cumple | APROBADO |
| maitre no accede a admin_reportes | Lo que dice el caso | se cumple | APROBADO |
| mesero no accede a admin_empleados | Lo que dice el caso | se cumple | APROBADO |
| mesero no accede a maitre_nueva | Lo que dice el caso | se cumple | APROBADO |
| cocinero no accede a admin_menu | Lo que dice el caso | se cumple | APROBADO |
| cocinero no accede a mesero_pedidos | Lo que dice el caso | se cumple | APROBADO |
| admin no accede a maitre_nueva | Lo que dice el caso | se cumple | APROBADO |
| admin no accede a cocinero_ordenes | Lo que dice el caso | se cumple | APROBADO |
| mesero no accede a cocinero_ordenes | Lo que dice el caso | se cumple | APROBADO |
| cocinero no accede a maitre_reservaciones | Lo que dice el caso | se cumple | APROBADO |
| POST sin sesión no agrega mesas | Lo que dice el caso | se cumple | APROBADO |
| POST de otro rol no agrega mesas | Lo que dice el caso | se cumple | APROBADO |
| muestra cupo total 72 | Lo que dice el caso | se cumple | APROBADO |
| agregar mesa suma al cupo | Lo que dice el caso | se cumple | APROBADO |
| modificar sillas | Lo que dice el caso | se cumple | APROBADO |
| rechaza mesa sin sillas, en español | Lo que dice el caso | se cumple | APROBADO |
| eliminar mesa sin historial | Lo que dice el caso | se cumple | APROBADO |
| rechaza eliminar mesa con historial, en español | Lo que dice el caso | se cumple | APROBADO |
| rechaza reducir sillas de una mesa en uso | Lo que dice el caso | La reservación 486 requiere 4 sillas a las 2026-11-06 07:29:00, pero sus mesas asignadas solo ofrecen 1. | APROBADO |
| modificar una mesa inexistente no informa éxito | Lo que dice el caso | se cumple | APROBADO |
| eliminar una mesa inexistente no informa éxito | Lo que dice el caso | se cumple | APROBADO |
| agregar plato | Lo que dice el caso | se cumple | APROBADO |
| guarda tiempo y categoría | Lo que dice el caso | se cumple | APROBADO |
| el menú muestra el plato nuevo con su categoría | Lo que dice el caso | se cumple | APROBADO |
| modificar plato | Lo que dice el caso | se cumple | APROBADO |
| rechaza precio negativo, en español | Lo que dice el caso | El precio debe ser un número mayor o igual a cero. | APROBADO |
| rechaza precio NaN | Lo que dice el caso | El precio debe ser un número mayor o igual a cero. | APROBADO |
| eliminar un plato inexistente no informa éxito | Lo que dice el caso | se cumple | APROBADO |
| la tabla del menú tiene tantas columnas como encabezados | Lo que dice el caso | se cumple | APROBADO |
| rechaza un plato sin nombre | Lo que dice el caso | Escriba el nombre y la descripción del plato. | APROBADO |
| eliminar plato sin pedidos | Lo que dice el caso | se cumple | APROBADO |
| rechaza eliminar plato ya pedido, en español | Lo que dice el caso | No se puede eliminar el plato porque ya fue pedido. | APROBADO |
| registrar cocinero | Lo que dice el caso | se cumple | APROBADO |
| la clave se guarda como hash, con fecha | Lo que dice el caso | se cumple | APROBADO |
| el empleado nuevo inicia sesión | Lo que dice el caso | se cumple | APROBADO |
| sin especialidades no ve órdenes | Lo que dice el caso | se cumple | APROBADO |
| sin órdenes lo dice | Lo que dice el caso | se cumple | APROBADO |
| asignar especialidad | Lo que dice el caso | se cumple | APROBADO |
| con especialidad ve la orden | Lo que dice el caso | se cumple | APROBADO |
| quitar especialidad | Lo que dice el caso | se cumple | APROBADO |
| modificar el nombre | Lo que dice el caso | se cumple | APROBADO |
| sin escribir clave, la clave no cambia | Lo que dice el caso | se cumple | APROBADO |
| la clave nueva permite entrar | Lo que dice el caso | se cumple | APROBADO |
| la clave anterior ya no sirve | Lo que dice el caso | se cumple | APROBADO |
| eliminar empleado sin historial | Lo que dice el caso | se cumple | APROBADO |
| rechaza eliminar empleado con historial | Lo que dice el caso | se cumple | APROBADO |
| ese rechazo está en español | Lo que dice el caso | No se puede eliminar el empleado porque tiene pedidos. | APROBADO |
| el administrador no se elimina a sí mismo | Lo que dice el caso | se cumple | APROBADO |
| ese rechazo lo explica | Lo que dice el caso | No puede eliminar su propia cuenta. | APROBADO |
| la sesión del administrador sigue activa | Lo que dice el caso | se cumple | APROBADO |
| rechaza empleado sin clave | Lo que dice el caso | se cumple | APROBADO |
| ese rechazo pide la clave | Lo que dice el caso | La clave es obligatoria. | APROBADO |
| solo registra maitres, meseros y cocineros | Lo que dice el caso | se cumple | APROBADO |
| ese rechazo pide un rol válido | Lo que dice el caso | Seleccione un rol de empleado válido. | APROBADO |
| modificar no actúa sobre clientes | Lo que dice el caso | Seleccione un empleado válido. | APROBADO |
| ese rechazo pide un empleado válido | Lo que dice el caso | se cumple | APROBADO |
| eliminar no actúa sobre un cliente sin historial | Lo que dice el caso | Seleccione un empleado válido. | APROBADO |
| la lista solo muestra empleados gestionados | Lo que dice el caso | se cumple | APROBADO |
| mesero sin pedidos lo ve indicado | Lo que dice el caso | se cumple | APROBADO |
| eliminar al mesero sin pedidos | Lo que dice el caso | se cumple | APROBADO |
| crear reservación con cliente nuevo | Lo que dice el caso | Reservación registrada. | APROBADO |
| tras crear enlaza a las reservaciones de ese día | Lo que dice el caso | se cumple | APROBADO |
| el cliente nuevo tiene rol cliente y no tiene clave | Lo que dice el caso | se cumple | APROBADO |
| el horario queda en la partición de 2027 | Lo que dice el caso | se cumple | APROBADO |
| rechaza cruce en la misma mesa | Lo que dice el caso | La mesa 2 ya tiene una reservación activa en ese horario. | APROBADO |
| permite ventana contigua, a las 2 horas exactas | Lo que dice el caso | Reservación registrada. | APROBADO |
| rechaza sillas insuficientes | Lo que dice el caso | La reservación 530 requiere 5 sillas a las 2027-03-03 12:00:00, pero sus mesas asignadas solo ofrecen 4. | APROBADO |
| permite una reservación con dos mesas | Lo que dice el caso | Reservación registrada. | APROBADO |
| rechaza superar el cupo total | Lo que dice el caso | El cupo del restaurante se supera a las 2027-03-10 12:00:00; ajuste las reservaciones o las mesas. | APROBADO |
| rechaza reservación sin mesa | Lo que dice el caso | Seleccione al menos una mesa. | APROBADO |
| rechaza una fecha imposible | Lo que dice el caso | Ingrese una fecha y hora válidas. | APROBADO |
| el error conserva lo escrito en el formulario | Lo que dice el caso | se cumple | APROBADO |
| rechaza reservación sin cliente, con mensaje claro | Lo que dice el caso | Seleccione un cliente o escriba el nombre de uno nuevo. | APROBADO |
| sin cliente no se crea ninguna reservación | Lo que dice el caso | se cumple | APROBADO |
| ese mensaje no habla de eliminar | Lo que dice el caso | se cumple | APROBADO |
| rechaza duración de 2 horas | Lo que dice el caso | La duración debe estar entre 1 y 119 minutos. | APROBADO |
| duración personalizable | Lo que dice el caso | se cumple | APROBADO |
| disponibilidad oculta una mesa con reserva dentro de 2 horas | Lo que dice el caso | se cumple | APROBADO |
| disponibilidad muestra una mesa libre | Lo que dice el caso | se cumple | APROBADO |
| disponibilidad muestra cupo | Lo que dice el caso | se cumple | APROBADO |
| disponibilidad avisa de una fecha inválida | Lo que dice el caso | se cumple | APROBADO |
| la pantalla de modificar precarga la duración | Lo que dice el caso | se cumple | APROBADO |
| modificar cantidad y duración | Lo que dice el caso | Reservación modificada. | APROBADO |
| mover de fecha cambia de partición | Lo que dice el caso | Reservación modificada. | APROBADO |
| modificar respeta sillas y deshace todo | Lo que dice el caso | se cumple | APROBADO |
| lista reservaciones de un día | Lo que dice el caso | se cumple | APROBADO |
| una reservada no ofrece Liberar | Lo que dice el caso | se cumple | APROBADO |
| una reservada ofrece Marcar ocupada y Cancelar | Lo que dice el caso | se cumple | APROBADO |
| marcar ocupada | Lo que dice el caso | se cumple | APROBADO |
| una ocupada ofrece Liberar y Cancelar, no Marcar ocupada | Lo que dice el caso | se cumple | APROBADO |
| liberar | Lo que dice el caso | se cumple | APROBADO |
| una liberada no ofrece acciones | Lo que dice el caso | se cumple | APROBADO |
| cambiar el estado de una reservación inexistente no informa éxito | Lo que dice el caso | se cumple | APROBADO |
| rechaza cambiar una liberada, en español y sin números de estado | Lo que dice el caso | No se puede modificar una reservación liberada o cancelada. | APROBADO |
| cancelar | Lo que dice el caso | se cumple | APROBADO |
| la mesa de una cancelada queda libre | Lo que dice el caso | Reservación registrada. | APROBADO |
| rechaza cancelar una reservación con pedidos | Lo que dice el caso | No se puede cancelar la reservación: uno de sus horarios tiene pedidos asociados. | APROBADO |
| avisa de una reservación próxima | Lo que dice el caso | se cumple | APROBADO |
| el bloque tiene id y opción para actualizarse | Lo que dice el caso | se cumple | APROBADO |
| la reservación lejana sí se creó | Lo que dice el caso | Reservación registrada. | APROBADO |
| no avisa de una reservación lejana | Lo que dice el caso | se cumple | APROBADO |
| solo ve órdenes de sus especialidades (2) | Lo que dice el caso | se cumple | APROBADO |
| las más demoradas primero | Lo que dice el caso | web: 973 975  sql: 973 975 | APROBADO |
| marcar listo | Lo que dice el caso | Orden marcada como lista. | APROBADO |
| la preparación queda a nombre de la sesión, no del formulario | Lo que dice el caso | se cumple | APROBADO |
| no marca dos veces la misma orden | Lo que dice el caso | se cumple | APROBADO |
| no prepara un plato sin especialidad | Lo que dice el caso | El cocinero 13 no tiene especialidad para el plato 1. | APROBADO |
| avisa al mesero cuando la orden está lista | Lo que dice el caso | se cumple | APROBADO |
| el aviso tiene id y opción para actualizarse | Lo que dice el caso | se cumple | APROBADO |
| el aviso dice la mesa de la orden | Lo que dice el caso | se cumple | APROBADO |
| el aviso trae el botón de entrega, para que aparezca sin recargar | Lo que dice el caso | se cumple | APROBADO |
| no avisa a otro mesero | Lo que dice el caso | se cumple | APROBADO |
| otro mesero no puede entregarla | Lo que dice el caso | se cumple | APROBADO |
| no entrega una orden sin preparar | Lo que dice el caso | se cumple | APROBADO |
| ofrece entregar la orden lista | Lo que dice el caso | se cumple | APROBADO |
| el botón dice qué orden entrega | Lo que dice el caso | se cumple | APROBADO |
| registrar la entrega | Lo que dice el caso | Orden marcada como entregada. | APROBADO |
| el aviso desaparece tras entregar | Lo que dice el caso | se cumple | APROBADO |
| lista la mesa con reservación vigente | Lo que dice el caso | se cumple | APROBADO |
| no lista una mesa cuya reservación es más tarde | Lo que dice el caso | se cumple | APROBADO |
| todas las mesas listadas abren el formulario de pedido | Lo que dice el caso | 0 sin formulario | APROBADO |
| sin sesión de mesero se rechaza el pedido | Lo que dice el caso | se cumple | APROBADO |
| sin sesión de mesero no se registra el pedido | Lo que dice el caso | se cumple | APROBADO |
| muestra el menú para pedir | Lo que dice el caso | se cumple | APROBADO |
| un solo botón de volver al menú | Lo que dice el caso | se cumple | APROBADO |
| el formulario de pedido también muestra el bloque de avisos | Lo que dice el caso | se cumple | APROBADO |
| rechaza un pedido sin platos | Lo que dice el caso | se cumple | APROBADO |
| registra un pedido con varios platos y cantidades | Lo que dice el caso | Pedido registrado. | APROBADO |
| el pedido queda en la mesa correcta | Lo que dice el caso | se cumple | APROBADO |
| el pedido queda a nombre del mesero de la sesión | Lo que dice el caso | se cumple | APROBADO |
| el cliente es el de la reservación de esa mesa | Lo que dice el caso | se cumple | APROBADO |
| lo ve en sus pedidos con estado | Lo que dice el caso | se cumple | APROBADO |
| rechaza pedir en una mesa sin reservación vigente | Lo que dice el caso | se cumple | APROBADO |
| el plato más demorado sale primero, aunque se pidió después | Lo que dice el caso | posiciones 1 y 4 | APROBADO |
| los tiempos de preparación nunca aumentan en la lista | Lo que dice el caso | se cumple | APROBADO |
| un pedido nuevo está En preparación | Lo que dice el caso | se cumple | APROBADO |
| con una orden lista, el pedido sigue En preparación | Lo que dice el caso | Orden marcada como lista. | APROBADO |
| con todas las órdenes listas, el pedido está Listo | Lo que dice el caso | Orden marcada como lista. | APROBADO |
| con una orden entregada, el pedido sigue Listo | Lo que dice el caso | Orden marcada como entregada. | APROBADO |
| con todas las órdenes entregadas, el pedido está Entregado | Lo que dice el caso | Orden marcada como entregada. | APROBADO |
| las órdenes de ese pedido muestran su estado | Lo que dice el caso | se cumple | APROBADO |
| agrega una mesa a una reservación con pedidos | Lo que dice el caso | Reservación modificada. | APROBADO |
| cambia la duración de una reservación con pedidos | Lo que dice el caso | se cumple | APROBADO |
| no quita la mesa del pedido | Lo que dice el caso | No se puede quitar ni mover este horario: tiene pedidos asociados. | APROBADO |
| no mueve de hora una reservación con pedidos | Lo que dice el caso | No se puede quitar ni mover este horario: tiene pedidos asociados. | APROBADO |
| esos rechazos dejan la reservación como estaba | Lo que dice el caso | se cumple | APROBADO |
| la mesa agregada tiene un número mayor, como requiere el caso siguiente | Lo que dice el caso | mesas 11 y 15 | APROBADO |
| quita una mesa agregada por error, que no es la del pedido | Lo que dice el caso | Reservación modificada. | APROBADO |
| el pedido sigue en su mesa | Lo que dice el caso | se cumple | APROBADO |
| horarios_1 está en ts_reservaciones_1 | Lo que dice el caso | se cumple | APROBADO |
| horarios_1 tiene datos | Lo que dice el caso | se cumple | APROBADO |
| horarios_2 está en ts_reservaciones_2 | Lo que dice el caso | se cumple | APROBADO |
| horarios_2 tiene datos | Lo que dice el caso | se cumple | APROBADO |
| horarios_3 está en ts_reservaciones_3 | Lo que dice el caso | se cumple | APROBADO |
| horarios_3 tiene datos | Lo que dice el caso | se cumple | APROBADO |
| los tablespaces están en directorios diferentes | Lo que dice el caso | se cumple | APROBADO |
| reservaciones por day: 139 filas | Lo que dice el caso | se cumple | APROBADO |
| ventas por day suman el total 41857000 | Lo que dice el caso | suma web: 41857000 | APROBADO |
| reservaciones por week: 36 filas | Lo que dice el caso | se cumple | APROBADO |
| ventas por week suman el total 41857000 | Lo que dice el caso | suma web: 41857000 | APROBADO |
| reservaciones por month: 10 filas | Lo que dice el caso | se cumple | APROBADO |
| ventas por month suman el total 41857000 | Lo que dice el caso | suma web: 41857000 | APROBADO |
| el plato más solicitado es Crema de ahuyama | Lo que dice el caso | web: Crema de ahuyama | APROBADO |
| la semana se lee como Semana del | Lo que dice el caso | se cumple | APROBADO |
| el mes se lee como AAAA-MM | Lo que dice el caso | se cumple | APROBADO |
| el día se lee como AAAA-MM-DD | Lo que dice el caso | se cumple | APROBADO |
| fechas inválidas en reportes no rompen la página | Lo que dice el caso | se cumple | APROBADO |
| reservaciones por day: cada valor coincide con la base | Lo que dice el caso | se cumple | APROBADO |
| ventas por day: cada valor coincide con la base | Lo que dice el caso | se cumple | APROBADO |
| reservaciones por week: cada valor coincide con la base | Lo que dice el caso | se cumple | APROBADO |
| ventas por week: cada valor coincide con la base | Lo que dice el caso | se cumple | APROBADO |
| reservaciones por month: cada valor coincide con la base | Lo que dice el caso | se cumple | APROBADO |
| ventas por month: cada valor coincide con la base | Lo que dice el caso | se cumple | APROBADO |
| platos más solicitados: cada valor coincide con la base | Lo que dice el caso | se cumple | APROBADO |
| periodo inválido no rompe la página | Lo que dice el caso | se cumple | APROBADO |
| historial muestra sus reservaciones | Lo que dice el caso | se cumple | APROBADO |
| historial muestra sus órdenes | Lo que dice el caso | se cumple | APROBADO |
| historial muestra la mesa de todos sus pedidos | Lo que dice el caso | 0 sin mesa | APROBADO |
| historial cuenta bien las reservaciones en estado Reservada | Lo que dice el caso | se cumple | APROBADO |
| historial cuenta bien las reservaciones en estado Ocupada | Lo que dice el caso | se cumple | APROBADO |
| historial cuenta bien las reservaciones en estado Liberada | Lo que dice el caso | se cumple | APROBADO |
| historial cuenta bien las reservaciones en estado Cancelada | Lo que dice el caso | se cumple | APROBADO |
| GET no modifica datos | Lo que dice el caso | se cumple | APROBADO |
| el plato con etiquetas sí se guardó | Lo que dice el caso | se cumple | APROBADO |
| escapa HTML en administrar menú | Lo que dice el caso | se cumple | APROBADO |
| escapa HTML en el menú público | Lo que dice el caso | se cumple | APROBADO |
| ids con texto se leen como número y no traen datos de otros | Lo que dice el caso | se cumple | APROBADO |
| campos enviados como lista no dan avisos en admin_reportes | Lo que dice el caso | se cumple | APROBADO |
| campos enviados como lista no dan avisos en maitre_reservaciones | Lo que dice el caso | se cumple | APROBADO |
| campos enviados como lista no dan avisos en maitre_disponibilidad | Lo que dice el caso | se cumple | APROBADO |
| campos enviados como lista no dan avisos en maitre_nueva | Lo que dice el caso | se cumple | APROBADO |
| sin avisos de PHP en '' | Lo que dice el caso | se cumple | APROBADO |
| sin avisos de PHP en 'desplegar_menu' | Lo que dice el caso | se cumple | APROBADO |
| sin avisos de PHP en 'realizar_pedidos' | Lo que dice el caso | se cumple | APROBADO |
| sin avisos de PHP en 'iniciar_sesion' | Lo que dice el caso | se cumple | APROBADO |
| sin avisos de PHP en admin_mesas | Lo que dice el caso | se cumple | APROBADO |
| sin avisos de PHP en admin_menu | Lo que dice el caso | se cumple | APROBADO |
| sin avisos de PHP en admin_empleados | Lo que dice el caso | se cumple | APROBADO |
| sin avisos de PHP en admin_especialidades | Lo que dice el caso | se cumple | APROBADO |
| sin avisos de PHP en admin_reportes | Lo que dice el caso | se cumple | APROBADO |
| sin avisos de PHP en admin_historial | Lo que dice el caso | se cumple | APROBADO |
| sin avisos de PHP en maitre_reservaciones | Lo que dice el caso | se cumple | APROBADO |
| sin avisos de PHP en maitre_nueva | Lo que dice el caso | se cumple | APROBADO |
| sin avisos de PHP en maitre_disponibilidad | Lo que dice el caso | se cumple | APROBADO |
| sin avisos de PHP en maitre_avisos | Lo que dice el caso | se cumple | APROBADO |
| sin avisos de PHP en mesero_pedidos | Lo que dice el caso | se cumple | APROBADO |
| sin avisos de PHP en mesero_avisos | Lo que dice el caso | se cumple | APROBADO |
| sin avisos de PHP en cocinero_ordenes | Lo que dice el caso | se cumple | APROBADO |
| fechas sin segundos en admin_historial | Lo que dice el caso | se cumple | APROBADO |
| fechas sin segundos en maitre_reservaciones | Lo que dice el caso | se cumple | APROBADO |
| fechas sin segundos en mesero_pedidos | Lo que dice el caso | se cumple | APROBADO |
| fechas sin segundos en cocinero_ordenes | Lo que dice el caso | se cumple | APROBADO |
| ninguna página visitada en estas pruebas mostró avisos de PHP | Lo que dice el caso | se cumple | APROBADO |
| control: el detector sí reconoce un aviso de PHP | Lo que dice el caso | se cumple | APROBADO |
| se publica el script que actualiza los avisos | Lo que dice el caso | se cumple | APROBADO |
| no se publica .aider.chat.history.md | Lo que dice el caso | código 404 | APROBADO |
| no se publica .aider.input.history | Lo que dice el caso | código 404 | APROBADO |
| no se publica sql/05_datos.sql | Lo que dice el caso | código 404 | APROBADO |
| no se publica docs/decisiones.md | Lo que dice el caso | código 404 | APROBADO |
| no se publica AGENTS.md | Lo que dice el caso | código 404 | APROBADO |
| cerrar sesión termina el acceso | Lo que dice el caso | se cumple | APROBADO |
