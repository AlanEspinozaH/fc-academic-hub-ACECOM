# Contrato de producto FC Academic Hub v1

## Estado

Aceptado como alcance objetivo para la versión 1.0.

## Objetivo

FC Academic Hub será un catálogo académico público de la Facultad de Ciencias.

Los visitantes podrán consultar carreras, cursos y metadatos de recursos. El
contenido de los archivos y su descarga requerirán una cuenta institucional
activa.

## Escala inicial

El piloto está orientado a aproximadamente 100 usuarios y cubre las carreras de
la Facultad de Ciencias.

La prioridad no es la escalabilidad masiva, sino:

- seguridad;
- moderación;
- derechos;
- bajo costo;
- operación simple;
- transferencia entre estudiantes.

## Acceso

| Elemento                        | Acceso        |
| ------------------------------- | ------------- |
| Página principal                | Público       |
| Carreras, planes y cursos       | Público       |
| Metadatos de recursos aprobados | Público       |
| Catálogo físico de libros       | Público       |
| Vista previa de archivos        | Institucional |
| Descarga de archivos            | Institucional |
| Contribución                    | Contributor   |
| Moderación                      | Moderator     |
| Administración                  | Administrator |

La vista previa tiene la misma autorización que la descarga.

## Archivos

La versión 1 admite:

- un único PDF principal por recurso;
- máximo 10 000 000 bytes;
- URL opcional hacia fuentes externas `.tex` o `.md`;
- ninguna compilación de LaTeX en el servidor;
- ninguna carga directa de `.tex`, `.md` o ZIP.

## Recursos

Tipos admitidos:

- syllabus;
- exam;
- solution;
- notes;
- assignment;
- laboratory;
- class-material;
- book-reference.

`has_solution` indica que el documento principal contiene una solución.

## Periodo académico

El periodo puede ser:

- exacto;
- aproximado;
- desconocido.

Un periodo exacto usa `academic_term_id`. Un periodo aproximado usa un año
aproximado. Un periodo desconocido no requiere ninguno de los dos.

## Derechos

Estados admitidos para la versión objetivo:

- pending;
- own-work;
- authorized;
- institutional;
- open-license;
- public-domain;
- bibliographic-reference-only;
- copyright-restricted.

Un PDF no puede almacenarse ni publicarse cuando sus derechos no lo permitan.

## Roles visibles

### Contributor

- crear recursos;
- editar borradores;
- subir PDF;
- corregir rechazados;
- reenviar.

### Moderator

- revisar recursos;
- abrir archivos pendientes;
- detectar duplicados;
- aprobar;
- rechazar;
- retirar contenido.

### Administrator

- asignar y revocar roles;
- desactivar usuarios;
- gestionar moderadores;
- responder a incidentes.

El rol `reviewer` puede permanecer internamente, pero no necesita una interfaz
separada en v1.

## Revisión

El flujo principal es:

```text
draft -> pending -> approved | rejected
```

Reglas:

- una aprobación es suficiente;
- el rechazo requiere comentario;
- un moderador no puede aprobar su propio recurso;
- un rechazado puede editarse y reenviarse;
- toda transición queda auditada.

## Duplicados

- SHA-256 identifica archivos idénticos;
- una coincidencia produce una advertencia;
- no se rechaza automáticamente;
- el moderador toma la decisión;
- un recurso aprobado no se sobrescribe.

## Retiro

Un recurso aprobado se retira lógicamente antes de eliminar su archivo.

Las solicitudes de retiro usan:

```text
open | accepted | rejected | resolved
```

La eliminación física es un procedimiento posterior y auditado.

## Catálogo físico

La versión 1 puede incluir un catálogo público simple de menos de 70 libros con:

- título;
- autor;
- edición;
- ISBN opcional;
- categoría;
- ubicación;
- estado físico;
- disponibilidad;
- observaciones.

No incluye préstamos avanzados, reservas, multas ni notificaciones.

## P0: piloto

- backend de subida;
- almacenamiento privado;
- portal contributor;
- portal moderator;
- catálogo dinámico;
- vista previa y descarga institucional;
- administración mínima;
- seguridad;
- despliegue;
- backups;
- documentación.

## P1: versión 1 completa

- solicitudes de retiro;
- detección visible de duplicados;
- catálogo físico;
- limpieza programada;
- transferencia administrativa.

## Fuera de alcance

- múltiples archivos;
- compilación LaTeX;
- OCR;
- búsqueda interna;
- comentarios;
- puntuaciones;
- IA;
- aplicación móvil;
- notificaciones;
- videos;
- préstamos avanzados;
- acceso público al contenido de los archivos.

## Definición de terminado

La versión 1 está terminada cuando el flujo completo de consulta, contribución,
revisión, publicación, vista previa, descarga, administración, auditoría,
despliegue, respaldo y transferencia está operativo y documentado.
