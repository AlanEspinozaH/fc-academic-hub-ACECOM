# Contrato de producto FC Academic Hub v1

## Estado

Aceptado como alcance objetivo para la versión 1.0.

Este documento describe el comportamiento objetivo del producto. Algunas capacidades pueden encontrarse todavía pendientes de implementación durante las etapas de desarrollo de la versión 1.

## Objetivo

FC Academic Hub será un catálogo académico público de la Facultad de Ciencias.

Los visitantes podrán consultar carreras, cursos y metadatos públicos de recursos sin autenticación.

Los archivos aprobados podrán tener una de las siguientes audiencias de publicación:

- `public`;
- `restricted`;
- `privileged`.

El acceso efectivo dependerá de:

- el estado de revisión del recurso;
- la audiencia aprobada;
- los derechos aplicables;
- la identidad y los privilegios del usuario cuando corresponda.

`private` se utiliza para recursos no publicados o dentro del workflow interno y no constituye una audiencia final de publicación.

La combinación:

```text
approved + private
```

es inválida en v1.

## Escala inicial

El piloto está orientado a aproximadamente 100 usuarios y cubre las carreras de la Facultad de Ciencias.

La prioridad no es la escalabilidad masiva, sino:

- seguridad;
- moderación;
- derechos;
- bajo costo;
- operación simple;
- transferencia entre estudiantes.

## Acceso

| Elemento                         | Acceso                                  |
| -------------------------------- | --------------------------------------- |
| Catálogo público                 | Público                                 |
| Metadatos aprobados públicos     | Público                                 |
| Archivo `public` aprobado        | Público, sin autenticación              |
| Archivo `restricted` aprobado    | Identidad institucional activa          |
| Archivo `privileged` aprobado    | Usuario activo con privilegio explícito |
| Contribución                     | Contributor                             |
| Revisión                         | Reviewer / Moderator                    |
| Publicación                      | Moderator                               |
| Gestión de privilegios y cuentas | Administrator                           |

La vista previa y la descarga de un mismo archivo están sujetas a la misma política de autorización.

En v1, los metadatos generales de un recurso y su archivo principal comparten la misma audiencia final.

Por tanto, un actor que no pueda acceder al recurso tampoco debe conocer mediante las interfaces ordinarias de consumo:

- su existencia;
- su título;
- sus metadatos generales;
- la existencia de su archivo principal.

Una vista mínima destinada al propietario para consultar el estado de su propia submission pertenece al workflow y no constituye exposición de los metadatos generales del recurso.

### Audiencia `public`

Un recurso `approved + public` puede ser consultado sin autenticación cuando sus derechos permiten publicación pública.

### Audiencia `restricted`

Un recurso `approved + restricted` está dirigido a la comunidad institucional ordinaria y requiere una identidad institucional activa.

Un usuario externo con privilegio especial no obtiene acceso a `restricted` únicamente por poseer ese privilegio.

### Audiencia `privileged`

`privileged` representa una audiencia especial de usuarios expresamente autorizados por el Centro de Estudiantes.

Puede incluir:

- identidades institucionales;
- identidades externas previamente admitidas.

El acceso privilegiado se concede a la cuenta del usuario mediante una autorización explícita independiente de sus roles editoriales.

El Moderator decide si un recurso aprobado tendrá audiencia `privileged`.

El Administrator gestiona qué usuarios reciben o pierden el privilegio necesario para acceder a dicha audiencia.

Un privilegio de acceso no convierte automáticamente al usuario en Contributor, Reviewer o Moderator.

En v1, una identidad:

```text
external_authorized
```

es exclusivamente lectora.

No puede recibir roles internos:

```text
student
contributor
reviewer
moderator
administrator
```

Puede recibir únicamente los entitlements explícitos admitidos por el producto, actualmente:

```text
privileged_material.read
```

## Archivos

La versión 1 admite:

- un único archivo principal por recurso;
- PDF;
- PNG y JPEG;
- Markdown;
- TeX;
- texto plano;
- código fuente con extensiones incluidas expresamente en la allowlist de v1;
- ninguna compilación de LaTeX en el servidor;
- ninguna ejecución de código o archivos aportados por usuarios.

Los límites de tamaño dependen de la familia del archivo:

- PDF, PNG y JPEG: máximo 10 000 000 bytes;
- Markdown, TeX, texto y código fuente: máximo 2 000 000 bytes.

Los archivos admitidos, extensiones exactas, validaciones, media types y reglas de presentación se definen en la política normativa de archivos.

HTML, SVG, ejecutables, archivos comprimidos, proyectos multiarchivo y otros formatos no incluidos expresamente en la allowlist quedan fuera de v1.

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

`has_solution` indica que el archivo principal contiene una solución.

## Periodo académico

El periodo puede ser:

- exacto;
- aproximado;
- desconocido.

Un periodo exacto usa `academic_term_id`.

Un periodo aproximado usa un año aproximado.

Un periodo desconocido no requiere ninguno de los dos.

## Derechos

Estados admitidos para la versión objetivo:

- `pending`;
- `own-work`;
- `authorized`;
- `institutional`;
- `open-license`;
- `public-domain`;
- `bibliographic-reference-only`;
- `copyright-restricted`.

`rights_status` establece qué distribución puede autorizarse para el recurso.

La audiencia seleccionada nunca puede ampliar los derechos disponibles.

Un archivo no puede almacenarse, aprobarse o publicarse cuando sus derechos no lo permitan.

### `institutional`

`institutional` no implica autorización automática para publicación abierta en Internet.

Como regla v1:

```text
institutional + public
```

no está permitido.

Puede utilizarse con `restricted` y, cuando la autorización institucional cubra expresamente esa audiencia, con `privileged`.

### `open-license` y `public-domain`

Estos estados pueden permitir publicación `public`, pero no obligan a que el recurso sea público.

El Moderator puede seleccionar una audiencia más limitada cuando corresponda.

### `authorized`

`authorized` significa que existe una autorización explícita documentada.

No implica automáticamente que la distribución pública esté permitida.

El Moderator debe seleccionar únicamente una audiencia cubierta por la autorización documentada.

En v1, la comprobación del alcance concreto de esa autorización forma parte de la revisión editorial y no se representa mediante un segundo enum de alcance legal.

## Roles visibles

### Contributor

- crear recursos;
- editar borradores propios;
- subir un archivo principal admitido;
- corregir recursos rechazados;
- reenviar recursos a revisión;
- proponer metadatos, derechos y audiencia.

El Contributor no decide la audiencia final de publicación.

### Reviewer

El rol `reviewer` puede permanecer disponible internamente sin necesitar una interfaz separada en v1.

Puede participar en la revisión de recursos `pending` según la política de acceso, pero no realiza la publicación final.

### Moderator

El Moderator es la autoridad editorial ordinaria sobre los recursos académicos.

Puede:

- revisar recursos pendientes;
- abrir archivos pendientes;
- detectar duplicados;
- aprobar;
- rechazar;
- determinar la audiencia final de publicación;
- retirar contenido según el procedimiento correspondiente.

El Contributor puede proponer una audiencia, pero el Moderator determina la audiencia final al aprobar el recurso, dentro de los derechos aplicables, incluidas las restricciones estructurales y el alcance de la evidencia documental cuando corresponda.

El Moderator no concede privilegios permanentes a cuentas de usuario.

### Administrator

El Administrator es la autoridad administrativa de la plataforma.

Puede:

- asignar y revocar roles;
- autorizar o revocar privilegios especiales;
- gestionar moderadores;
- gestionar la admisión administrativa de identidades externas;
- suspender o desactivar cuentas;
- responder a incidentes;
- realizar las intervenciones administrativas excepcionales previstas por el sistema.

La administración de cuentas y privilegios debe permanecer separada de la decisión editorial ordinaria sobre los recursos.

## Moderación

El sistema admite múltiples usuarios con rol `moderator`.

Para el piloto, el objetivo operativo es mantener al menos dos moderadores activos para reducir dependencia de una sola persona y permitir revisión cuando uno de ellos sea propietario del recurso o no esté disponible.

No existe un límite estructural de dos moderadores.

La versión 1 no requiere consenso de múltiples moderadores para aprobar un recurso.

Una única aprobación válida es suficiente.

## Revisión

El flujo principal es:

```text
draft -> pending -> approved | rejected
```

Reglas:

- una aprobación válida es suficiente;
- el rechazo requiere comentario;
- un Moderator no puede aprobar su propio recurso;
- un Moderator no puede acceder a borradores o rechazados ajenos únicamente por ser Moderator;
- Reviewer y Moderator pueden acceder a recursos `pending` según la política de revisión;
- Administrator conserva las capacidades administrativas excepcionales definidas por la política de acceso;
- un recurso rechazado puede editarse y reenviarse;
- toda transición relevante queda auditada;
- ninguna audiencia de publicación permite saltarse `review_status`.
- una vez aprobado un recurso, ownership no concede un bypass de la audiencia final; el propietario consume el recurso según las mismas reglas ordinarias de audiencia;
- Reviewer no conserva acceso editorial general después de la aprobación; su acceso a un recurso `approved` depende de la audiencia final, salvo que posea otra autoridad explícita independiente;

## Duplicados

- SHA-256 identifica archivos idénticos;
- una coincidencia produce una advertencia;
- no se rechaza automáticamente;
- el Moderator toma la decisión;
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
- portal Contributor;
- portal Moderator;
- catálogo dinámico;
- vista previa y descarga según audiencia `public`, `restricted` o `privileged`;
- administración mínima de cuentas, roles y privilegios;
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

- múltiples archivos por recurso;
- compilación LaTeX;
- ejecución de código subido;
- renderizado activo de HTML aportado por usuarios;
- SVG;
- archivos comprimidos y proyectos multiarchivo;
- OCR;
- búsqueda interna dentro del contenido;
- comentarios;
- puntuaciones;
- IA;
- aplicación móvil;
- notificaciones;
- videos;
- préstamos avanzados;
- ACL individual por recurso;
- linking complejo de múltiples identidades para una misma cuenta.

## Definición de terminado

La versión 1 está terminada cuando el flujo completo de consulta, contribución, revisión, publicación, vista previa, descarga, administración, auditoría, despliegue, respaldo y transferencia está operativo, probado y documentado de acuerdo con los contratos normativos aceptados.
