-- La clave primaria incluye la columna de partición, como exige PostgreSQL 13.
CREATE TABLE horarios (
    id SERIAL NOT NULL,
    mesa_id INTEGER NOT NULL,
    reservacion_id INTEGER NOT NULL,
    inicio TIMESTAMP WITHOUT TIME ZONE NOT NULL,
    duracion INTERVAL NOT NULL,
    CONSTRAINT pk_horarios PRIMARY KEY (id, inicio),
    CONSTRAINT ck_horarios_duracion CHECK (
        duracion > INTERVAL '0' AND duracion < INTERVAL '2 hours'
    ),
    CONSTRAINT fk_horarios_mesa FOREIGN KEY (mesa_id)
        REFERENCES mesas (id) ON DELETE RESTRICT,
    CONSTRAINT fk_horarios_reservacion FOREIGN KEY (reservacion_id)
        REFERENCES reservaciones (id) ON DELETE RESTRICT
) PARTITION BY RANGE (inicio);

CREATE TABLE horarios_1 PARTITION OF horarios
    FOR VALUES FROM (MINVALUE) TO ('2026-10-01 00:00:00')
    TABLESPACE ts_reservaciones_1;

CREATE TABLE horarios_2 PARTITION OF horarios
    FOR VALUES FROM ('2026-10-01 00:00:00') TO ('2027-01-01 00:00:00')
    TABLESPACE ts_reservaciones_2;

CREATE TABLE horarios_3 PARTITION OF horarios
    FOR VALUES FROM ('2027-01-01 00:00:00') TO (MAXVALUE)
    TABLESPACE ts_reservaciones_3;

CREATE INDEX ix_horarios_mesa_inicio ON horarios (mesa_id, inicio);
CREATE INDEX ix_horarios_reservacion_id ON horarios (reservacion_id);
CREATE INDEX ix_horarios_inicio ON horarios (inicio);
CREATE INDEX ix_horarios_id ON horarios (id);
