-- Estructura base. Las restricciones relacionales se agregan en 02.

CREATE TABLE roles (
    id SERIAL PRIMARY KEY,
    nombre TEXT NOT NULL
);

CREATE TABLE tipos (
    id SERIAL PRIMARY KEY,
    nombre TEXT NOT NULL
);

CREATE TABLE usuarios (
    id SERIAL PRIMARY KEY,
    nombre TEXT NOT NULL,
    clave BYTEA,
    fecha_clave TIMESTAMP
);

CREATE TABLE mesas (
    id SERIAL PRIMARY KEY,
    sillas INTEGER NOT NULL
);

CREATE TABLE reservaciones (
    id SERIAL PRIMARY KEY,
    cliente_id INTEGER NOT NULL,
    cantidad INTEGER NOT NULL,
    estado INTEGER NOT NULL
);

CREATE TABLE platos (
    id SERIAL PRIMARY KEY,
    tipo_id INTEGER NOT NULL,
    nombre TEXT NOT NULL,
    descripcion TEXT NOT NULL,
    tiempo INTERVAL NOT NULL,
    precio NUMERIC NOT NULL
);

CREATE TABLE actuaciones (
    id SERIAL PRIMARY KEY,
    rol_id INTEGER NOT NULL,
    usuario_id INTEGER NOT NULL
);

CREATE TABLE especialidades (
    id SERIAL PRIMARY KEY,
    cocinero_id INTEGER NOT NULL,
    plato_id INTEGER NOT NULL
);

CREATE TABLE pedidos (
    id SERIAL PRIMARY KEY,
    cliente_id INTEGER NOT NULL,
    mesero_id INTEGER NOT NULL
);

CREATE TABLE ordenes (
    id SERIAL PRIMARY KEY,
    plato_id INTEGER NOT NULL,
    pedido_id INTEGER NOT NULL,
    estado INTEGER NOT NULL,
    cantidad INTEGER NOT NULL,
    solicitado TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE TABLE preparaciones (
    id SERIAL PRIMARY KEY,
    cocinero_id INTEGER NOT NULL,
    orden_id INTEGER NOT NULL
);
