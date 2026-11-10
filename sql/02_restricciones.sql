-- Reglas declarativas e índices para relaciones y consultas habituales.

ALTER TABLE usuarios
    ADD CONSTRAINT ck_usuarios_nombre_no_vacio
        CHECK (btrim(nombre) <> ''),
    ADD CONSTRAINT ck_usuarios_clave_fecha_juntas
        CHECK ((clave IS NULL) = (fecha_clave IS NULL));

ALTER TABLE roles
    ADD CONSTRAINT uq_roles_nombre UNIQUE (nombre);

ALTER TABLE tipos
    ADD CONSTRAINT uq_tipos_nombre UNIQUE (nombre),
    ADD CONSTRAINT ck_tipos_categoria
        CHECK (nombre IN ('entrada', 'plato fuerte', 'postre', 'bebida'));

ALTER TABLE actuaciones
    ADD CONSTRAINT uq_actuaciones_usuario_rol UNIQUE (usuario_id, rol_id),
    ADD CONSTRAINT fk_actuaciones_rol FOREIGN KEY (rol_id)
        REFERENCES roles (id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_actuaciones_usuario FOREIGN KEY (usuario_id)
        REFERENCES usuarios (id) ON DELETE CASCADE;

ALTER TABLE platos
    ADD CONSTRAINT uq_platos_nombre UNIQUE (nombre),
    ADD CONSTRAINT ck_platos_precio_valido CHECK (precio >= 0 AND precio <> 'NaN'),
    ADD CONSTRAINT ck_platos_tiempo_positivo CHECK (tiempo > INTERVAL '0'),
    ADD CONSTRAINT fk_platos_tipo FOREIGN KEY (tipo_id)
        REFERENCES tipos (id) ON DELETE RESTRICT;

ALTER TABLE mesas
    ADD CONSTRAINT ck_mesas_sillas_positivas CHECK (sillas > 0);

ALTER TABLE reservaciones
    ADD CONSTRAINT ck_reservaciones_cantidad_positiva CHECK (cantidad > 0),
    ADD CONSTRAINT ck_reservaciones_estado CHECK (estado IN (0, 1, 2, 3)),
    ALTER COLUMN estado SET DEFAULT 0,
    ADD CONSTRAINT fk_reservaciones_cliente FOREIGN KEY (cliente_id)
        REFERENCES usuarios (id) ON DELETE RESTRICT;

ALTER TABLE ordenes
    ADD CONSTRAINT ck_ordenes_cantidad_positiva CHECK (cantidad > 0),
    ADD CONSTRAINT ck_ordenes_estado CHECK (estado IN (0, 1, 2)),
    ALTER COLUMN estado SET DEFAULT 0,
    ALTER COLUMN solicitado SET DEFAULT now(),
    ADD CONSTRAINT fk_ordenes_plato FOREIGN KEY (plato_id)
        REFERENCES platos (id) ON DELETE RESTRICT;

ALTER TABLE pedidos
    ADD CONSTRAINT fk_pedidos_cliente FOREIGN KEY (cliente_id)
        REFERENCES usuarios (id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_pedidos_mesero FOREIGN KEY (mesero_id)
        REFERENCES usuarios (id) ON DELETE RESTRICT;

ALTER TABLE ordenes
    ADD CONSTRAINT fk_ordenes_pedido FOREIGN KEY (pedido_id)
        REFERENCES pedidos (id) ON DELETE RESTRICT;

ALTER TABLE especialidades
    ADD CONSTRAINT uq_especialidades_cocinero_plato UNIQUE (cocinero_id, plato_id),
    ADD CONSTRAINT fk_especialidades_cocinero FOREIGN KEY (cocinero_id)
        REFERENCES usuarios (id) ON DELETE CASCADE,
    ADD CONSTRAINT fk_especialidades_plato FOREIGN KEY (plato_id)
        REFERENCES platos (id) ON DELETE CASCADE;

ALTER TABLE preparaciones
    ADD CONSTRAINT uq_preparaciones_orden_cocinero UNIQUE (orden_id, cocinero_id),
    ADD CONSTRAINT fk_preparaciones_cocinero FOREIGN KEY (cocinero_id)
        REFERENCES usuarios (id) ON DELETE RESTRICT,
    ADD CONSTRAINT fk_preparaciones_orden FOREIGN KEY (orden_id)
        REFERENCES ordenes (id) ON DELETE RESTRICT;

CREATE INDEX ix_actuaciones_rol_id ON actuaciones (rol_id);
CREATE INDEX ix_platos_tipo_id ON platos (tipo_id);
CREATE INDEX ix_reservaciones_cliente_estado ON reservaciones (cliente_id, estado);
CREATE INDEX ix_reservaciones_estado ON reservaciones (estado);
CREATE INDEX ix_pedidos_cliente_id ON pedidos (cliente_id);
CREATE INDEX ix_pedidos_mesero_id ON pedidos (mesero_id);
CREATE INDEX ix_ordenes_plato_id ON ordenes (plato_id);
CREATE INDEX ix_ordenes_pedido_solicitado ON ordenes (pedido_id, solicitado);
CREATE INDEX ix_especialidades_plato_id ON especialidades (plato_id);
CREATE INDEX ix_preparaciones_cocinero_id ON preparaciones (cocinero_id);
CREATE INDEX ix_preparaciones_orden_id ON preparaciones (orden_id);
