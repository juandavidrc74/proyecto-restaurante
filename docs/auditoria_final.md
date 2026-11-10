# Auditoría final

Comprueba cada requisito de `2026.3-ProyectoRestaurante.pdf` contra lo construido y busca todo lo que no se pidió. Los nombres de las pruebas son los de [resultados_pruebas.md](resultados_pruebas.md), que se generó de las salidas reales, sin los datos que varían de una ejecución a otra, como una cantidad.

Estados:

- **Cumple:** hay implementación y una prueba ejecutada que lo demuestra.
- **Cumple, interpretación confirmada:** funciona y depende de una interpretación que el usuario confirmó el 2026-11-08 ([decisiones.md](decisiones.md), sección 13).
- **Sin automatizar:** se comprobó de otra forma, que se indica.
- **Pendiente del usuario:** no se puede resolver desde el código.

## 1. Matriz de trazabilidad

### Descripción general (PDF, sección 1)

| Requisito | Implementación | Archivo/objeto | Prueba | Estado |
|---|---|---|---|---|
| Gestionar mesas, reservaciones, menús, pedidos y entregas | Pantallas por rol | `lib/administrador.php`, `lib/maitre.php`, `lib/mesero.php`, `lib/cocinero.php` | Baterías 02 y 03 | Cumple |
| No superar el cupo | Trigger con ventana de 2 horas y bloqueo | `validar_cupo_ventana`, `tr_horarios_validar_inmediato` | superar cupo se rechaza; rechaza superar el cupo total; cupo: la segunda sesión es rechazada por cupo | Cumple |
| No cruzar reservaciones | Trigger por mesa y bloqueo | `validar_cruce_horario` | cruce en la misma mesa se rechaza; rechaza cruce en la misma mesa; cruce: la segunda sesión es rechazada | Cumple |
| Cocineros solo con los platos que saben | Especialidades y comprobación al preparar | `especialidades`, `comprobar_preparacion` | preparación requiere especialidad del plato; no prepara un plato sin especialidad | Cumple |

### Roles (PDF, sección 2)

| Requisito | Implementación | Archivo/objeto | Prueba | Estado |
|---|---|---|---|---|
| Administrador: gestionar mesas, menú y empleados | Pantallas Mesas, Administrar menú y Empleados | `fn_admin_mesas`, `fn_admin_menu`, `fn_admin_empleados` | Secciones de administrador de la batería 03 | Cumple |
| Administrador: registrar maitres, meseros y cocineros | Formulario con esos tres roles | `registrar_empleado` | registrar cocinero; solo registra maitres, meseros y cocineros | Cumple |
| Administrador: asignar platos a cocineros | Casillas por cocinero | `fn_admin_especialidades` | asignar especialidad; quitar especialidad | Cumple |
| Administrador: reportes de ventas, reservaciones y pedidos | Pantalla Reportes | `fn_admin_reportes` | Ver sección 3.6 | Cumple |
| Maitre: recibir y gestionar reservaciones | Reservaciones y Nueva reservación | `fn_maitre_reservaciones`, `fn_maitre_nueva` | crear reservación con cliente nuevo; lista reservaciones de un día | Cumple |
| Maitre: asignar mesas según disponibilidad | Consulta de mesas libres y casillas de mesas | `fn_maitre_disponibilidad`, `consultar_disponibilidad` | disponibilidad oculta una mesa con reserva dentro de 2 horas; disponibilidad muestra una mesa libre | Cumple |
| Maitre: crear, cancelar y modificar | Formularios y botones por estado | `crear_reservacion`, `cambiar_estado_reservacion`, `modificar_reservacion` | cancelar; modificar cantidad y duración; agrega una mesa a una reservación con pedidos; quita una mesa agregada por error, que no es la del pedido; no quita la mesa del pedido | Cumple, interpretación confirmada: lo que ya tiene pedidos no se mueve ni se cancela |
| Maitre: verificar cupo y cruces | Disponibilidad y mensajes de los triggers | `consultar_disponibilidad`, triggers de `horarios` | disponibilidad muestra cupo; rechaza cruce en la misma mesa | Cumple |
| Mesero: registrar pedidos en cada mesa | Realizar Pedido | `pedido_mesa`, `registrar_pedido` | registra un pedido con varios platos y cantidades | Cumple |
| Mesero: actualizar el estado (en preparación, listo, entregado) | "Entregado" lo marca el mesero; "En preparación" es automático; "Listo" lo marca el cocinero, porque el diagrama exige una preparación con cocinero | `entregar_orden`, `preparar_orden`, `validar_orden` | un pedido nuevo está En preparación; con todas las órdenes listas, el pedido está Listo; con todas las órdenes entregadas, el pedido está Entregado; orden no pasa a preparada sin preparación | Cumple, interpretación confirmada |
| Mesero: gestionar entregas | Aviso con botón de entrega | `fn_mesero_avisos`, `fn_mesero_pedidos` | registrar la entrega; otro mesero no puede entregarla; no entrega una orden sin preparar | Cumple |
| Cocinero: ver pedidos, los más demorados primero, solo los que sabe preparar | Consulta por especialidad con `ORDER BY p.tiempo DESC` | `fn_cocinero_ordenes` | el plato más demorado sale primero, aunque se pidió después; solo ve órdenes de sus especialidades | Cumple |
| Cocinero: actualizar a "listo" | Botón Marcar listo | `preparar_orden` | marcar listo; la preparación queda a nombre de la sesión, no del formulario | Cumple |
| Cliente: reservar por medio del maitre | El cliente no inicia sesión; el maitre registra | `fn_maitre_nueva` | un cliente no puede iniciar sesión; crear reservación con cliente nuevo | Cumple |
| Cliente: pedir por medio del mesero | El pedido se asocia al cliente de la mesa | `registrar_pedido` | el cliente es el de la reservación de esa mesa | Cumple |

### Casos de uso (PDF, sección 3)

| Requisito | Implementación | Archivo/objeto | Prueba | Estado |
|---|---|---|---|---|
| 3.1 Agregar, modificar y eliminar mesas con sus asientos | Tabla con acciones por fila | `fn_admin_mesas`, `procesar_formulario_mesas` | agregar mesa suma al cupo; modificar sillas; eliminar mesa sin historial | Cumple |
| 3.1 Identificador único y número de asientos | SERIAL y CHECK | `mesas`, `ck_mesas_sillas_positivas` | identificador de mesa único; mesas con sillas positivas; rechaza mesa sin sillas, en español | Cumple |
| 3.1 Calcular el cupo total | `SUM(sillas) OVER ()` | `fn_admin_mesas`, `sql/06_consultas.sql` | muestra cupo total 72; agregar mesa suma al cupo | Cumple |
| 3.2 Registrar reservaciones con mesa y horario | Formulario de reservación | `crear_reservacion`, `insertar_horarios` | crear reservación con cliente nuevo; permite una reservación con dos mesas | Cumple |
| 3.2 Sin cruces en la misma mesa | Trigger | `validar_cruce_horario` | cruce en la misma mesa se rechaza; ventanas contiguas permitidas; mover horario que crea cruce se rechaza | Cumple |
| 3.2 Cupo sin superar, con ocupación de 2 horas | Barrido de los instantes de la ventana | `validar_cupo_ventana` | superar cupo se rechaza; rechaza superar el cupo total | Cumple |
| 3.2 Validar que la mesa esté disponible | Trigger y consulta de disponibilidad | `validar_cruce_horario`, `consultar_disponibilidad` | rechaza cruce en la misma mesa; disponibilidad oculta una mesa con reserva dentro de 2 horas | Cumple |
| 3.3 Gestionar el menú con las cuatro categorías | Pantalla Administrar menú y CHECK | `fn_admin_menu`, `ck_tipos_categoria` | categoría de tipo limitada; el menú muestra el plato nuevo con su categoría | Cumple |
| 3.3 Nombre, descripción, precio, tiempo y categoría | Columnas de `platos` | `sql/01_estructura.sql`, `formulario_plato` | guarda tiempo y categoría; rechaza un plato sin nombre | Cumple |
| 3.3 Agregar, modificar y eliminar ítems | Formularios | `procesar_formulario_menu` | agregar plato; modificar plato; eliminar plato sin pedidos | Cumple |
| 3.4 Registrar pedidos por mesa | Lista de mesas vigentes y formulario | `fn_realizar_pedidos`, `pedido_mesa` | todas las mesas listadas abren el formulario de pedido; no lista una mesa cuya reservación es más tarde; rechaza pedir en una mesa sin reservación vigente | Cumple, interpretación confirmada: solo se listan las mesas con reservación vigente |
| 3.4 Pedido asociado a una mesa y un cliente | Cliente en `pedidos`; mesa derivada, porque el diagrama no la guarda | `mesa_de_pedido`, `pedidos_detalle` | el pedido queda en la mesa correcta; mesa de pedido con dos mesas devuelve la menor | Cumple (aceptado por el usuario el 2026-11-05) |
| 3.4 Agregar múltiples ítems a un pedido | Una cantidad por plato en el formulario | `cantidades_por_plato`, `registrar_pedido` | registra un pedido con varios platos y cantidades | Cumple, interpretación confirmada: se agregan al crear el pedido |
| 3.4 Actualizar el estado (en preparación, listo, entregado) | Estados de orden y estado derivado del pedido | `validar_orden`, `pedidos_detalle` | un pedido nuevo está En preparación; con una orden lista, el pedido sigue En preparación; con todas las órdenes listas, el pedido está Listo; con una orden entregada, el pedido sigue Listo; con todas las órdenes entregadas, el pedido está Entregado; retroceso de estado de orden se rechaza; salto de estado de orden se rechaza | Cumple, interpretación confirmada: quién actualiza cada estado |
| 3.5 Registrar la entrega | Botón Entregar orden | `entregar_orden` | registrar la entrega | Cumple |
| 3.5 Notificar al mesero | Ver sección 4.1 | `fn_mesero_avisos` | Ver sección 4.1 | Cumple |
| 3.5 Actualizar a "entregado" | UPDATE con estado y mesero comprobados | `entregar_orden` | registrar la entrega; con todas las órdenes entregadas, el pedido está Entregado; el aviso desaparece tras entregar | Cumple |
| 3.6 Reservaciones por día, semana o mes | `date_trunc` sobre el primer inicio | `fn_admin_reportes` | reservaciones por day, por week y por month: cada valor coincide con la base | Cumple, interpretación confirmada: rango de fechas y sin canceladas |
| 3.6 Pedidos más solicitados | Suma de cantidades por plato | `fn_admin_reportes` | el plato más solicitado es Crema de ahuyama; platos más solicitados: cada valor coincide con la base | Cumple |
| 3.6 Ventas totales por día, semana o mes | Cantidad por precio de órdenes entregadas | `fn_admin_reportes` | ventas por day, por week y por month: cada valor coincide con la base; ventas por day, week y month suman el total | Cumple (precio actual, aceptado en decisiones, sección 12) |

### Funcionalidades adicionales (PDF, sección 4)

| Requisito | Implementación | Archivo/objeto | Prueba | Estado |
|---|---|---|---|---|
| 4.1 Notificar al mesero | Bloque de avisos que se actualiza cada 30 segundos | `fn_mesero_avisos`, `lib/programa.js` | avisa al mesero cuando la orden está lista; no avisa a otro mesero; el aviso dice la mesa de la orden. La actualización sin recargar se comprobó a mano en el navegador sobre la versión final | Cumple |
| 4.1 Notificar al maitre | Bloque de avisos en todas sus pantallas | `aviso_reservaciones_html`, `lib/programa.js` | avisa de una reservación próxima; no avisa de una reservación lejana. La actualización sin recargar se comprobó a mano en el navegador sobre la versión final | Cumple |
| 4.2 Registrar y gestionar empleados | Registrar, cambiar nombre y clave, eliminar | `fn_admin_empleados` | registrar cocinero; modificar el nombre; la clave nueva permite entrar; eliminar empleado sin historial; modificar no actúa sobre clientes | Cumple, interpretación confirmada: el rol no se cambia |
| 4.3 Historial de reservaciones y pedidos por cliente | Pantalla Historial | `fn_admin_historial` | historial muestra sus reservaciones; historial muestra sus órdenes; historial muestra la mesa de todos sus pedidos; historial cuenta bien las reservaciones en estado Liberada | Cumple |
| 4.4 Validar el cupo al asignar mesas | Triggers de `horarios`, `reservaciones` y `mesas` | `tr_horarios_validar_inmediato`, `tr_reservaciones_activa_diferida`, `tr_mesas_validar_sillas` | superar cupo se rechaza; reducir sillas con asignación se rechaza; cambiar cantidad revalida las sillas | Cumple |
| 4.5 Interfaz intuitiva por rol | Menú por rol, mensajes en español, botones solo para acciones permitidas | `fn_menu_opciones`, `acciones_reservacion` | administrador ve sus accesos; cocinero no ve accesos de administrador; una reservada no ofrece Liberar. El recorrido visual se hizo a mano | Sin automatizar: el usuario evalúa si es "intuitiva" |

### Requisitos técnicos (PDF, sección 6)

| Requisito | Implementación | Archivo/objeto | Prueba | Estado |
|---|---|---|---|---|
| 6.1 PostgreSQL | PostgreSQL 13 en la máquina virtual | `sql/01` a `sql/04` | Baterías 01 y 02 | Cumple |
| 6.1 Al menos 2 tablespaces en directorios diferentes | 3 tablespaces reutilizados | `ts_reservaciones_1`, `_2` y `_3` | los tablespaces están en directorios diferentes; horarios_1 está en ts_reservaciones_1 | Cumple |
| 6.1 Particionar una tabla por fechas | `horarios` por rango de `inicio` | `sql/03_tablespaces_particiones.sql` | horarios_1 tiene datos; mover de fecha cambia de partición; el horario queda en la partición de 2027 | Cumple |
| 6.2 Usar la plantilla como base | Plantilla conservada; cambios listados en [documentacion.md](documentacion.md), sección 9 | `index.php`, `lib/libreria.php`, `lib/restaurante.php` | menú público conserva Desplegar Menu y Realizar Pedido. Comparación con el original | Cumple |
| 6.2 Conservar la solución del docente | No aplica, según indicó el usuario el 2026-11-05 | `docs/decisiones.md`, sección 1 | No aplica | Aceptado por el usuario |
| 6.3 Claves primarias, foráneas, CHECK y triggers | Ver [documentacion.md](documentacion.md), sección 5 | `sql/01` a `sql/04` | Batería 01 completa | Cumple |
| 6.4 Diagrama ER y diccionario de datos | Documentado y comparado con el catálogo | `docs/documentacion.md`, secciones 2 y 3 | Comparación con `pruebas/resultados/04_catalogo.txt`, salida de `pruebas/04_catalogo.sql` | Cumple |
| 6.4 Consultas SQL y su funcionalidad | Documentadas por caso de uso | `docs/documentacion.md`, sección 9 | `sql/06_consultas.sql` corre sin errores | Cumple |
| 6.5 Pruebas | 328 casos automáticos y un recorrido a mano | `pruebas/`, `docs/resultados_pruebas.md` | 328 aprobados, 0 fallidos | Cumple |

### Entregables, evaluación y fecha (PDF, secciones 7 a 10)

| Requisito | Implementación | Archivo/objeto | Prueba | Estado |
|---|---|---|---|---|
| 7.1 Scripts de base, tablas, restricciones y datos | Scripts numerados | `sql/00` a `sql/05`, `sql/reconstruir.sql` | `pruebas/05_instalacion_limpia.sh`: `sql/00` con sus `CREATE TABLESPACE`, reconstrucción y carga sin errores, en un clúster temporal con directorios temporales | Cumple |
| 7.1 Consultas para cada caso de uso | Consultas y escrituras revertidas | `sql/06_consultas.sql` | Corre completo con `ON_ERROR_STOP`; no cambia los datos; ninguna consulta sale vacía con los datos recién cargados | Cumple |
| 7.2 Documento de diseño, casos de uso, tablespaces, particiones y consultas | Documento completo | `docs/documentacion.md` | Revisión | Cumple |
| 7.3 Sustentación oral | Fuera del código | No aplica | No aplica | Pendiente del usuario |
| 9 Uso de inteligencia artificial | Declarado | `docs/documentacion.md`, sección 12 | No aplica | Cumple |
| 10 Fecha de entrega 2026-10-09 | El usuario indicó el 2026-11-08 que la fecha real es el 2026-11-09 | No aplica | No aplica | Aceptado por el usuario |

## 2. Auditoría negativa

Se buscó todo lo que no pidió el PDF.

### Lo que no existe

| Se buscó | Cómo | Resultado |
|---|---|---|
| Tablas nuevas | Lista de `CREATE TABLE` en `sql/` y `pruebas/resultados/04_catalogo.txt` | Solo las 12 del diagrama y las 3 particiones de `horarios` |
| Columnas nuevas | `pruebas/resultados/04_catalogo.txt` comparado con el diagrama | Ninguna |
| Relaciones nuevas | Claves foráneas de `pruebas/resultados/04_catalogo.txt` | Solo las del diagrama |
| Facturación, pagos, inventario, domicilios, configuración, auditoría, analítica adicional | Lista de las funciones `fn_` y de las pantallas | Ninguno |
| Integraciones externas | Búsqueda de `curl_`, `mail(`, `fopen`, `exec(`, direcciones `http` y subida de archivos en `lib/` e `index.php` | Ninguna |
| Dependencias o frameworks | Archivos del proyecto | Ninguno: PHP y JavaScript sin bibliotecas |

Las únicas opciones de la aplicación son estas 20 funciones `fn_`. Cada una responde a un requisito o viene de la plantilla:

- **Plantilla:** `fn_boton_menu_principal`, `fn_menu_opciones`, `fn_desplegar_menu`, `fn_realizar_pedidos`.
- **Sesión:** `fn_iniciar_sesion`, `fn_cerrar_sesion`.
- **Administrador:** `fn_admin_mesas`, `fn_admin_menu`, `fn_admin_empleados`, `fn_admin_especialidades`, `fn_admin_reportes`, `fn_admin_historial`.
- **Maitre:** `fn_maitre_reservaciones`, `fn_maitre_nueva`, `fn_maitre_disponibilidad`, `fn_maitre_modificar`, `fn_maitre_avisos`.
- **Mesero:** `fn_mesero_pedidos`, `fn_mesero_avisos`.
- **Cocinero:** `fn_cocinero_ordenes`.

### Lo que no está escrito en el PDF y se conserva

| Elemento | Motivo | Situación |
|---|---|---|
| Inicio de sesión con empleado y clave | Sin él no hay interfaz por rol (4.5). El diagrama tiene `clave` | Aprobado, decisiones sección 10 |
| El maitre registra clientes nuevos | Sin esto, un cliente nuevo no podría reservar | Aprobado, decisiones sección 12 |
| Plazo del aviso al maitre en `etc/parametros.php` | El PDF no dice cuánto es "próxima a comenzar" | Aprobado, decisiones sección 11 |
| Vista `pedidos_detalle` y función `mesa_de_pedido` | El diagrama no guarda la mesa ni el estado del pedido | Aprobado, decisiones sección 4 |
| Una orden exige una reservación vigente del cliente, así que no hay clientes de paso | El usuario indicó que todo cliente pasa antes por el maitre | Aprobado, decisiones sección 4 |
| Las mesas de una reservación deben sumar sus personas | Sin esto, la asignación de mesas no garantizaría que quepan | Aprobado, decisiones sección 8 |
| Índices | Eficiencia de las consultas, que el PDF evalúa | Permitido por las reglas |
| `ck_usuarios_nombre_no_vacio`, `ck_usuarios_clave_fecha_juntas` | Integridad de `usuarios` | Permitido por las reglas |
| `uq_platos_nombre`, parte `NaN` de `ck_platos_precio_valido` | Integridad del menú y de las ventas | Aprobado, decisiones sección 13 |
| El administrador no puede eliminar su propia cuenta | Perdería el acceso y nadie podría administrar | Aprobado, decisiones sección 13 |
| El reporte de reservaciones no cuenta las canceladas | Una reservación cancelada no ocurrió | Aprobado, decisiones sección 13 |
| Triggers que protegen lo que ya tiene pedidos, aunque la aplicación no ofrezca esas operaciones | La integridad se exige en la base, no solo en la pantalla. Algunos no tienen camino desde la aplicación, y son lo primero que se podría quitar si se quiere un `sql/04` más corto | Aprobado, decisiones sección 13 |
| Rango de fechas en Reportes | Cubre las dos lecturas de "por día, semana o mes": agrupar y consultar un periodo concreto | Aprobado, decisiones sección 13 |
| Parámetros de la cookie de sesión | Protegen la sesión con `HttpOnly` y `SameSite`. No son indispensables para que funcione | Se conservan; se pueden quitar sin afectar ningún requisito |
| `pruebas/`, `README.md`, `.gitattributes` y `AGENTS.md` | Herramientas de desarrollo y evidencia. No se publican en el sitio; `AGENTS.md`, las reglas que se le dieron a Codex, ni siquiera está en Git | No forman parte de la aplicación |

### Lo que se quitó en esta auditoría

- Filtro por categoría en Administrar menú. El menú sigue saliendo ordenado por categoría; el usuario aceptó el 2026-11-08 que esto cubre "Consultar por categoría" ([decisiones.md](decisiones.md), sección 13).
- Lista "Reservaciones del día" en Nueva reservación.
- Comentarios y sangrías de la plantilla que se habían cambiado sin necesidad.
- Código que nunca actuaba: la comprobación del rol de mesero al entregar, el trigger de `horarios` al borrar que solo repetía el bloqueo, y mensajes de restricciones que PHP filtra antes.

## 3. Resultado

Todos los requisitos que se pueden comprobar desde el código tienen implementación y evidencia, y el usuario confirmó el 2026-11-08 las aclaraciones de [decisiones.md](decisiones.md), sección 13. Falta que el usuario resuelva:

1. **Evaluar si la interfaz es intuitiva para cada rol,** como pide la sección 4.5 del PDF.
2. **Preparar la sustentación oral.** Antes de presentarla, hay que volver a cargar `sql/05_datos.sql`, para que haya mesas ocupadas y reservaciones próximas.
