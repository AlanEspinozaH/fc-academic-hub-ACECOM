# Política de archivos de recursos académicos

## Estado

Decisión: **Aceptada**

Implementación: **allowlist v1 completa hasta Stage 4C.4**

Este documento define el contrato normativo de archivos aceptados por FC Academic Hub v1.

Describe:

- tipos de archivo admitidos;
- extensiones permitidas;
- clasificación mediante `file_kind`;
- límites de tamaño;
- validación server-side;
- media types canónicos;
- tratamiento de texto;
- presentación segura;
- descarga;
- nombres de archivo;
- hashing;
- almacenamiento privado;
- compatibilidad de `storage_key`.

Stage 4C.4 habilita operacionalmente la allowlist v1 completa: PDF, PNG, JPEG, Markdown, TeX, TXT y las extensiones source expresamente permitidas.

---

# 1. Propósito

FC Academic Hub debe aceptar distintos tipos de material académico sin convertir el sistema en un repositorio arbitrario de archivos.

La política v1 sigue cuatro principios:

1. **allowlist cerrada** de formatos;
2. todos los uploads son datos no confiables;
3. el servidor valida y clasifica el archivo;
4. almacenar un archivo nunca implica ejecutarlo o interpretarlo como código activo.

El soporte de formatos debe crecer únicamente mediante una modificación explícita de esta política.

---

# 2. Principios de seguridad

Todo archivo aportado por un usuario se considera:

```text
untrusted input
```

independientemente de:

- quién lo haya subido;
- su rol;
- el nombre del archivo;
- su extensión;
- el media type declarado por el navegador;
- su procedencia académica.

La aplicación puede:

- validar;
- almacenar;
- calcular hash;
- recuperar;
- mostrar de manera segura;
- permitir descarga.

La aplicación no debe:

- ejecutar código subido;
- compilar código;
- compilar LaTeX;
- ejecutar scripts;
- interpretar HTML aportado por usuarios;
- confiar únicamente en extensión o MIME del cliente;
- convertir automáticamente contenido textual en contenido activo.

---

# 3. Un archivo por recurso

FC Academic Hub v1 admite:

```text
máximo un archivo principal por recurso académico
```

Esta restricción es independiente del formato.

No se implementan en v1:

- múltiples anexos;
- proyectos multiarchivo;
- directorios;
- paquetes;
- archivos ZIP que representen proyectos.

Si en el futuro se admite más de un archivo por recurso, deberá modificarse explícitamente el contrato de producto y esta política.

---

# 4. Modelo canónico `ResourceFile`

El concepto general es:

```text
ResourceFile
```

y no:

```text
ResourcePdf
```

El modelo persistente objetivo debe disponer conceptualmente de:

```text
id
resource_id
uploaded_by
display_filename
file_kind
normalized_extension
content_type
byte_size
sha256
storage_key_version
created_at
updated_at
```

Este documento no obliga a que todos los nombres físicos de columnas sean exactamente esos, pero la implementación debe poder representar esas propiedades sin volver a inferir información crítica desde el nombre del archivo.

---

# 5. `file_kind`

Los valores admitidos en v1 son:

```text
pdf
image
markdown
tex
text
source
```

`file_kind` representa la semántica principal del archivo dentro del producto.

No representa necesariamente su media type exacto.

Por ejemplo:

```text
file_kind = image
content_type = image/png
```

y:

```text
file_kind = image
content_type = image/jpeg
```

son dos representaciones válidas.

---

# 6. Familias internas

Para reutilizar validaciones, una implementación puede agrupar internamente los formatos en tres familias:

```text
binary-document
raster-image
utf8-text
```

o una clasificación equivalente.

Esto es una decisión interna.

El contrato persistente debe conservar los seis `file_kind` definidos anteriormente.

En particular:

```text
markdown
tex
source
text
```

no deben reducirse permanentemente a un único `file_kind = text`, porque pueden adquirir comportamientos distintos en versiones futuras.

---

# 7. Allowlist v1

La allowlist es cerrada.

Solo se admiten las siguientes extensiones.

## PDF

```text
.pdf
```

## Raster images

```text
.png
.jpg
.jpeg
```

## Markdown

```text
.md
```

## TeX

```text
.tex
```

## Plain text

```text
.txt
```

## Source code

```text
.java
.py
.c
.h
.cpp
.hpp
.js
.ts
.rs
.go
.sql
.sh
```

Ninguna otra extensión está admitida en v1.

---

# 8. Extensiones no implícitas

Una extensión no puede considerarse permitida simplemente porque sea:

- textual;
- popular;
- académicamente útil;
- parecida a otra extensión admitida.

Por ejemplo, v1 no permite automáticamente:

```text
.cs
.kt
.rb
.php
.swift
.json
.yaml
.yml
.xml
.css
.m
.ipynb
```

Añadir cualquiera de ellas requiere primero modificar esta política.

La ausencia de una extensión en la denylist no significa que esté permitida.

---

# 9. Denylist explicativa

La seguridad real se basa en la allowlist.

La siguiente denylist documenta formatos particularmente fuera de alcance:

```text
.svg

.html
.htm
.xhtml
.xml

.zip
.rar
.7z
.tar
.gz

.exe
.dll
.so
.dylib
.msi
.apk

.jar
.war
.wasm

.doc
.docx
.xls
.xlsx
.ppt
.pptx

.ipynb
```

También se rechazan:

- binarios arbitrarios;
- paquetes de dependencias;
- proyectos multiarchivo;
- archivos comprimidos;
- ejecutables;
- formatos activos no aprobados.

Esta lista no pretende enumerar todas las extensiones rechazadas.

Cualquier extensión no incluida expresamente en la allowlist es rechazada.

---

# 10. HTML

HTML no está admitido en v1 incluso cuando se presente como código fuente.

Por tanto:

```text
.html
.htm
.xhtml
```

deben ser rechazados.

Una futura versión puede reconsiderarlos exclusivamente como código fuente servido siempre como `text/plain`, pero dicha capacidad requiere una modificación explícita de esta política y pruebas de seguridad específicas.

---

# 11. SVG

SVG está explícitamente rechazado en v1.

No debe:

- almacenarse como imagen admitida;
- mostrarse inline;
- reinterpretarse como texto admitido;
- aceptarse por tener MIME `image/svg+xml`.

El soporte de imágenes v1 se limita a:

```text
PNG
JPEG
```

---

# 12. Límites de tamaño

Los límites son decimales.

## PDF

```text
10 000 000 bytes
```

## PNG

```text
10 000 000 bytes
```

## JPEG

```text
10 000 000 bytes
```

## Markdown

```text
2 000 000 bytes
```

## TeX

```text
2 000 000 bytes
```

## TXT

```text
2 000 000 bytes
```

## Source code

```text
2 000 000 bytes
```

Un archivo vacío es inválido.

Por tanto:

```text
byte_size >= 1
```

es obligatorio.

---

# 13. Límite HTTP global

El endpoint de upload puede utilizar un límite HTTP global basado en el archivo máximo permitido por v1 más un margen acotado para multipart.

Conceptualmente:

```text
max supported file size
+
bounded multipart overhead
```

El límite HTTP global no sustituye los límites específicos por familia.

Por ejemplo, que el body HTTP permita aproximadamente 10 MB no significa que un archivo `.py` de 8 MB sea válido.

La validación específica deberá rechazarlo por superar:

```text
2 000 000 bytes
```

---

# 14. Media types canónicos

La aplicación debe persistir un `content_type` normalizado y decidido server-side.

La matriz v1 es:

| `file_kind` | Extensión        | `content_type` canónico |
| ----------- | ---------------- | ----------------------- |
| `pdf`       | `.pdf`           | `application/pdf`       |
| `image`     | `.png`           | `image/png`             |
| `image`     | `.jpg`, `.jpeg`  | `image/jpeg`            |
| `markdown`  | `.md`            | `text/plain`            |
| `tex`       | `.tex`           | `text/plain`            |
| `text`      | `.txt`           | `text/plain`            |
| `source`    | allowlist source | `text/plain`            |

Para respuestas HTTP textuales se utiliza:

```text
text/plain; charset=utf-8
```

El parámetro `charset=utf-8` pertenece a la representación HTTP y no necesita almacenarse necesariamente dentro de `resource_files.content_type`.

---

# 15. MIME enviado por el cliente

El media type declarado mediante:

```text
File.type
```

o cualquier header o campo controlado por el cliente es únicamente información diagnóstica.

No participa como autoridad en la aceptación del formato.

La autoridad es:

```text
allowlisted extension
+
content/signature validation
```

Después de validar el archivo, el servidor asigna el `content_type` canónico definido por esta política.

Por ejemplo:

```text
filename = foto.png
client MIME = image/jpeg
bytes = PNG válido
```

puede aceptarse y canonicalizarse como:

```text
file_kind = image
content_type = image/png
```

En cambio:

```text
filename = foto.png
client MIME = image/png
bytes = JPEG
```

debe rechazarse.

La misma regla aplica a PDF y archivos textuales.

Por ejemplo:

```text
filename = documento.pdf
client MIME = application/octet-stream
bytes = PDF válido
```

puede aceptarse y canonicalizarse como:

```text
content_type = application/pdf
```

Y:

```text
filename = dijkstra.py
client MIME = application/octet-stream
```

puede aceptarse si cumple las reglas de source code y canonicalizarse como:

```text
file_kind = source
content_type = text/plain
```

---

# 16. Clasificación server-side

La aplicación debe determinar el formato utilizando una política server-side.

Conceptualmente:

```text
filename / normalized extension
          +
content validation
          +
format-specific signatures when applicable
          ↓
validated ResourceFile
```

No se permite:

```text
client says image/png
→ trust image/png
```

---

# 17. Dispatcher de validación

La implementación debe ofrecer conceptualmente una operación general:

```text
validateResourceFile(...)
```

que seleccione la estrategia correspondiente.

Por ejemplo:

```text
validateResourceFile
    │
    ├── PDF
    │     └── PDF validator
    │
    ├── PNG
    │     └── PNG validator
    │
    ├── JPEG
    │     └── JPEG validator
    │
    └── textual
          └── UTF-8 text validator
```

No es necesario utilizar clases u orientación a objetos.

El validador PDF especializado existente puede conservarse detrás del dispatcher general.

---

# 18. Validación común

Todos los archivos deben cumplir como mínimo:

```text
non-empty
supported extension
safe filename
family-specific size limit
content validation
SHA-256
```

Cuando exista una firma binaria conocida, también debe comprobarse.

---

# 19. Nombre del archivo

`display_filename` conserva el nombre presentado al usuario.

Todo filename recibido del cliente se considera no confiable.

La política v1 es:

1. eliminar whitespace únicamente de los extremos del nombre;
2. rechazar si después de ese trim el nombre queda vacío;
3. rechazar caracteres ASCII de control, incluidos `U+0000` a `U+001F` y `U+007F`;
4. rechazar explícitamente CR y LF;
5. rechazar `/`;
6. rechazar `\`;
7. rechazar nombres que representen rutas o componentes de traversal;
8. conservar el nombre resultante en cualquier otro caso.

La aplicación no renombra automáticamente archivos para corregir nombres inválidos.

Por tanto:

```text
"  tarea.pdf  "
-> "tarea.pdf"
```

es válido después del trim.

Pero:

```text
../tarea.pdf
carpeta/tarea.pdf
carpeta\tarea.pdf
filename con CR/LF
```

deben rechazarse.

La construcción de `Content-Disposition` es una responsabilidad separada y debe utilizar un encoder o builder seguro.

Nunca debe concatenarse directamente `display_filename` dentro de una cabecera HTTP.

---

# 20. Extensión normalizada

La aplicación debe derivar una extensión normalizada en minúsculas.

Ejemplos:

```text
TAREA.PDF
→ .pdf
```

```text
FOTO.JPEG
→ .jpeg
```

El nombre visible puede conservar una representación apropiada para el usuario, pero la clasificación interna utiliza la extensión normalizada.

---

# 21. Renombrado automático de formato

La aplicación no debe corregir automáticamente contradicciones entre nombre y contenido.

Ejemplo:

```text
filename = foto.png
bytes = JPEG
```

Resultado:

```text
REJECT
```

No:

```text
rename to foto.jpg
```

La corrección debe realizarla el usuario y requerir una nueva subida.

---

# 22. Validación PDF

Un PDF válido para v1 debe cumplir:

```text
safe filename
normalized extension = .pdf
1 <= byte_size <= 10 000 000
PDF header compatible with %PDF-
PDF EOF marker validation
SHA-256
```

La validación actual especializada de PDF debe preservarse mientras siga cumpliendo este contrato.

No se realiza interpretación funcional del contenido PDF.

No se ejecutan acciones, scripts o contenido embebido desde el servidor.

---

# 23. Validación PNG

Un PNG debe cumplir:

```text
safe filename
normalized extension = .png
1 <= byte_size <= 10 000 000
PNG signature exacta en offset 0:
89 50 4E 47 0D 0A 1A 0A
SHA-256
```

La implementación debe comparar exactamente estos ocho bytes desde el inicio del archivo.

La firma PNG esperada debe validarse sobre los bytes del archivo.

No basta con:

```text
filename = *.png
```

ni:

```text
client MIME = image/png
```

---

# 24. Validación JPEG

Un JPEG debe cumplir:

```text
safe filename
normalized extension = .jpg or .jpeg
1 <= byte_size <= 10 000 000
JPEG SOI/marker-prefix/EOI validation
SHA-256
```

El criterio binario mínimo v1 es:

```text
offset 0:
FF D8

offset 2:
FF

final del archivo:
FF D9
```

Por tanto, el archivo debe:

- comenzar con el marcador JPEG SOI `FF D8`;
- tener `FF` como siguiente prefijo de marcador;
- terminar con el marcador JPEG EOI `FF D9`.

La implementación no necesita realizar parsing ni decoding completo de JPEG en v1.

---

# 25. Dimensiones de imagen

V1 no define un límite estructurado de ancho, alto o megapíxeles.

La protección principal es:

```text
allowlist
+
signature validation
+
10 000 000 byte limit
```

La aplicación no debe añadir procesamiento pesado de imágenes, generación de thumbnails o decoding server-side como parte de esta etapa.

Si en una futura versión se realizan transformaciones o thumbnails, deberán evaluarse límites de dimensiones y riesgos de decompression bombs.

---

# 26. Validación textual

Se consideran textuales:

```text
markdown
tex
text
source
```

Todos deben cumplir:

```text
safe filename
allowlisted extension
1 <= byte_size <= 2 000 000
valid UTF-8
no NUL bytes
SHA-256
```

---

# 27. UTF-8

Los archivos textuales deben contener UTF-8 válido.

Un archivo con secuencias UTF-8 inválidas debe rechazarse.

No debe intentarse convertir automáticamente desde:

- Latin-1;
- Windows-1252;
- otras codificaciones.

El usuario deberá proporcionar un archivo UTF-8 válido.

---

# 28. UTF-8 BOM

Un BOM UTF-8 inicial está permitido.

Los bytes originales se conservan.

Por tanto:

```text
stored bytes
```

incluyen el BOM si fue aportado.

El SHA-256 se calcula sobre esos mismos bytes.

El preview puede evitar mostrar visualmente el BOM inicial, sin modificar el objeto almacenado.

---

# 29. Saltos de línea

Se admiten:

```text
LF
CRLF
```

La aplicación no debe normalizar:

```text
CRLF -> LF
```

durante almacenamiento.

Esto preserva:

- bytes originales;
- SHA-256;
- descarga exacta del archivo aportado.

---

# 30. NUL

Los archivos textuales no pueden contener:

```text
NUL
```

Un NUL detectado en un archivo:

```text
.md
.tex
.txt
source
```

produce rechazo.

Esto ayuda a evitar aceptar binarios disfrazados de texto.

---

# 31. Markdown

Markdown se almacena como datos textuales.

En v1:

```text
file_kind = markdown
content_type = text/plain
preview = plain text
```

No se renderiza como HTML.

No se utiliza:

```text
innerHTML
```

para insertar su contenido.

Markdown rendering queda fuera de v1.

---

# 32. TeX

TeX se almacena como texto no confiable.

En v1:

```text
file_kind = tex
content_type = text/plain
preview = plain text
```

No se:

- compila;
- ejecuta;
- interpreta mediante LaTeX;
- procesa mediante shell escape;
- convierte a PDF automáticamente.

La plataforma almacena y muestra el source de manera conservadora.

---

# 33. Source code

El código fuente se trata exclusivamente como texto.

En v1:

```text
file_kind = source
content_type = text/plain
preview = plain text
```

No se:

- compila;
- ejecuta;
- interpreta;
- evalúa;
- instala;
- resuelve dependencias.

Por ejemplo, un archivo:

```text
solution.py
```

es material académico para lectura y descarga, no código que FC Academic Hub deba ejecutar.

---

# 34. TXT

Los `.txt` se clasifican como:

```text
file_kind = text
content_type = text/plain
```

y siguen las mismas reglas UTF-8 de las demás familias textuales.

---

# 35. Hash SHA-256

Todos los archivos admitidos deben tener SHA-256.

El hash se calcula sobre:

```text
los bytes originales exactos que se almacenarán
```

No sobre una versión:

- normalizada;
- decodificada;
- reserializada;
- transformada.

Por tanto:

```text
upload bytes
=
hashed bytes
=
stored bytes
```

salvo operaciones técnicas que no alteren su contenido.

---

# 36. Duplicados

SHA-256 puede utilizarse para detectar archivos idénticos.

Una coincidencia no implica rechazo automático.

El comportamiento de producto respecto a duplicados se mantiene separado de la validación de formato.

Un archivo puede ser:

```text
format-valid
```

y simultáneamente:

```text
duplicate candidate
```

La decisión editorial pertenece al workflow de revisión.

---

# 37. Preview

La presentación v1 es conservadora.

| Tipo     | Preview      |
| -------- | ------------ |
| PDF      | inline PDF   |
| PNG      | inline image |
| JPEG     | inline image |
| Markdown | plain text   |
| TeX      | plain text   |
| TXT      | plain text   |
| source   | plain text   |

---

# 38. Content-Type de preview

Las respuestas de preview utilizan:

```text
PDF
application/pdf
```

```text
PNG
image/png
```

```text
JPEG
image/jpeg
```

Para cualquier tipo textual:

```text
text/plain; charset=utf-8
```

Nunca se debe devolver contenido textual aportado por usuarios como:

```text
text/html
```

---

# 39. `nosniff`

Las respuestas de archivos deben incluir cuando corresponda:

```text
X-Content-Type-Options: nosniff
```

El navegador no debe ser invitado a reinterpretar el contenido usando sniffing de MIME.

---

# 40. Download

Todo archivo autorizado puede descargarse.

La descarga debe utilizar una disposición apropiada:

```text
Content-Disposition: attachment
```

y un filename construido mediante una función segura.

No debe concatenarse directamente un nombre aportado por el usuario dentro de una cabecera HTTP.

---

# 41. Inline preview

PDF, PNG y JPEG pueden utilizar:

```text
Content-Disposition: inline
```

cuando se solicite preview.

Los archivos textuales se muestran como texto plano independientemente de que conceptualmente sean Markdown, TeX o código fuente.

---

# 42. Preview y download comparten autorización

Esta política define cómo se presenta el archivo, pero no quién puede verlo.

La autorización se define en:

```text
docs/architecture/resource-access-contract.md
```

Preview y download deben exigir la misma autorización sobre el recurso.

La presentación no puede convertirse en un bypass de acceso.

---

# 43. No `innerHTML`

El contenido textual aportado por usuarios nunca debe insertarse mediante:

```text
innerHTML
```

u otra API equivalente que lo convierta accidentalmente en markup activo.

Cuando una interfaz necesite mostrar texto, debe utilizar una representación que preserve su naturaleza textual.

---

# 44. No ejecución

La aplicación nunca ejecuta el archivo almacenado.

Esta regla incluye explícitamente:

```text
.py
.js
.ts
.sh
.java
.c
.cpp
.rs
.go
.sql
.tex
```

Que una extensión esté admitida significa:

> FC Academic Hub puede almacenarla y mostrarla de forma segura.

No significa:

> FC Academic Hub puede ejecutarla.

---

# 45. Almacenamiento R2

Cloudflare R2 permanece privado.

Todos los archivos de usuario pueden compartir el mismo bucket privado independientemente de su audiencia lógica:

```text
public
restricted
privileged
private/workflow
```

La visibilidad del recurso no determina la visibilidad física del objeto R2.

---

# 46. `storage_key`

`storage_key` es metadata interna de infraestructura.

No debe:

- devolverse al navegador;
- aparecer en APIs públicas;
- utilizarse como identificador de producto;
- aceptarse libremente como input del cliente;
- considerarse una credencial de autorización.

El cliente trabaja con identificadores del dominio, como:

```text
resource_id
file_id
```

---

# 47. Layout legacy

Los objetos creados por el contrato PDF anterior pueden utilizar:

```text
resources/<resource_id>/<file_id>.pdf
```

Este esquema se denomina conceptualmente:

```text
legacy_pdf_v1
```

Los objetos existentes no deben renombrarse únicamente para ajustarse al nuevo diseño.

---

# 48. Layout genérico

Los nuevos objetos creados después de la migración correspondiente deben utilizar:

```text
resources/<resource_id>/<file_id>
```

sin extensión derivada del formato.

Este esquema se denomina conceptualmente:

```text
generic_v2
```

---

# 49. `storage_key_version`

El sistema necesita distinguir de forma explícita qué layout utiliza un archivo.

Conceptualmente:

```text
storage_key_version =
  legacy_pdf_v1
  generic_v2
```

El nombre físico exacto de la columna o enum puede definirse durante implementación, pero la información no debe inferirse utilizando únicamente:

- fecha de creación;
- MIME;
- `file_kind`;
- suposición de que todos los PDFs son legacy.

---

# 50. Resolución de storage

Conceptualmente:

```text
legacy_pdf_v1
    ↓
resources/<resource_id>/<file_id>.pdf
```

```text
generic_v2
    ↓
resources/<resource_id>/<file_id>
```

La aplicación server-side puede derivar el objeto utilizando:

```text
resource_id
file_id
storage_key_version
```

sin exponer el `storage_key` privado al navegador.

---

# 51. Autoridad del storage

`private.resource_storage_objects.storage_key` puede continuar siendo la autoridad interna sobre la referencia física almacenada.

Agregar metadata no sensible para resolver el layout no convierte `storage_key` en información pública.

El contrato de storage debe continuar evitando grants directos innecesarios sobre claves privadas.

---

# 52. Nuevos archivos

Una vez implementado el layout genérico:

```text
todos los nuevos uploads
→ generic_v2
```

incluidos nuevos PDFs.

Por tanto:

```text
PDF antiguo
→ podría terminar en .pdf

PDF nuevo
→ no necesita terminar en .pdf
```

El formato vive en PostgreSQL mediante metadata canónica y no en la key del objeto.

---

# 53. No migración física automática

Stage 4C no requiere:

- copiar todos los objetos legacy;
- renombrarlos;
- eliminarlos;
- reescribir R2.

La compatibilidad dual es preferible a una migración física sin necesidad funcional.

---

# 54. URLs públicas

Esta política no introduce:

- public bucket URLs;
- URLs permanentes de objetos;
- signed URLs como mecanismo principal de acceso.

La recuperación continúa mediada por la aplicación server-side y la política de autorización.

---

# 55. Errores

Los errores de validación deben ser:

- seguros;
- suficientemente específicos para corregir el upload;
- incapaces de revelar datos internos.

Ejemplos apropiados:

```text
Unsupported file extension
File exceeds maximum size
Invalid PNG file
File must contain valid UTF-8
Text files cannot contain NUL bytes
Filename is not valid
```

No deben revelar:

- storage keys;
- SQL interno;
- secretos;
- rutas físicas;
- datos de otros usuarios.

---

# 56. Política central

Las reglas de formato deben estar centralizadas conceptualmente.

La implementación TypeScript debería disponer de una política equivalente a:

```text
format
→ file kind
→ accepted extensions
→ canonical content type
→ max bytes
→ validation strategy
→ preview mode
```

No deben existir allowlists divergentes repartidas arbitrariamente entre:

- endpoint;
- UI;
- R2;
- validator;
- componentes.

Las restricciones PostgreSQL pueden reflejar invariantes críticas como defensa en profundidad, pero no deben contradecir la política normativa.

---

# 57. Cambios en allowlist

Codex o cualquier implementación futura no puede añadir por conveniencia:

```text
.json
.yaml
.php
.cs
.kt
...
```

sin:

1. modificar este documento;
2. justificar el formato;
3. definir validación;
4. definir MIME canónico;
5. definir preview;
6. definir límites;
7. añadir pruebas.

---

# 58. Invariantes normativas

## RF-01 — Closed allowlist

Solo se aceptan extensiones presentes expresamente en la allowlist v1.

---

## RF-02 — Untrusted uploads

Todos los archivos de usuario son datos no confiables.

---

## RF-03 — One file per resource

Un recurso admite como máximo un archivo principal en v1.

---

## RF-04 — Canonical classification

El servidor determina `file_kind`, extensión normalizada y `content_type` canónico.

---

## RF-05 — Client MIME is diagnostic only

El MIME enviado por el cliente es únicamente diagnóstico y nunca constituye una condición autoritativa de aceptación.

El servidor determina el formato mediante extensión permitida y validación del contenido, y posteriormente asigna el `content_type` canónico.

---

## RF-06 — Binary signatures

PDF, PNG y JPEG requieren validación de contenido mediante las firmas o invariantes definidas para cada formato.

---

## RF-07 — Extension/content consistency

Una extensión incompatible con el contenido real produce rechazo.

---

## RF-08 — UTF-8 text

Markdown, TeX, TXT y source deben contener UTF-8 válido.

---

## RF-09 — NUL rejection

Los archivos textuales no pueden contener NUL.

---

## RF-10 — Preserve original bytes

BOM, CRLF y LF permitidos se conservan en almacenamiento sin normalización de bytes.

---

## RF-11 — Hash exact bytes

SHA-256 se calcula sobre los bytes exactos almacenados.

---

## RF-12 — Plain-text presentation

Markdown, TeX, TXT y source se presentan como:

```text
text/plain; charset=utf-8
```

---

## RF-13 — No active rendering

La aplicación no renderiza HTML aportado por usuarios ni utiliza uploaded Markdown como HTML en v1.

---

## RF-14 — No execution

Ningún archivo aportado por usuarios se ejecuta, compila o interpreta como programa.

---

## RF-15 — Private R2

R2 permanece privado independientemente de `visibility`.

---

## RF-16 — Private storage key

`storage_key` nunca forma parte del contrato público del cliente.

---

## RF-17 — Generic new layout

Los nuevos objetos posteriores a la migración correspondiente utilizan el layout genérico sin extensión.

---

## RF-18 — Legacy compatibility

Los objetos legacy `.pdf` continúan siendo resolubles sin renombrarlos.

---

## RF-19 — No MIME sniffing

Las respuestas de archivos utilizan media types controlados y `X-Content-Type-Options: nosniff` cuando corresponda.

---

## RF-20 — Safe Content-Disposition

Los filenames aportados por usuarios no se interpolan directamente en `Content-Disposition`.

---

# 59. Pruebas normativas requeridas

La implementación debe demostrar como mínimo los siguientes casos.

## PDF

```text
valid PDF -> allow
empty PDF -> reject
oversized PDF -> reject
wrong extension -> reject
invalid header -> reject
missing/invalid EOF condition -> reject
hash generated -> expected SHA-256
valid .pdf + client MIME application/octet-stream
-> allow
-> canonical content type = application/pdf
```

---

## PNG

```text
valid PNG -> allow
oversized PNG -> reject
.png with JPEG bytes -> reject
invalid PNG signature -> reject
canonical content type -> image/png
.png + valid PNG bytes + client MIME image/jpeg
-> allow
-> canonical content type = image/png
```

---

## JPEG

```text
valid .jpg -> allow
valid .jpeg -> allow
oversized JPEG -> reject
.jpg with PNG bytes -> reject
invalid JPEG signature -> reject
canonical content type -> image/jpeg
.jpg + valid JPEG bytes + client MIME application/octet-stream
-> allow
-> canonical content type = image/jpeg
```

---

## Text

```text
valid UTF-8 .txt -> allow
empty .txt -> reject
oversized .txt -> reject
invalid UTF-8 -> reject
NUL byte -> reject
UTF-8 BOM -> allow
LF -> allow
CRLF -> allow
```

---

## Markdown

```text
valid .md -> allow
HTML-like text inside .md -> allow as text
preview content type -> text/plain; charset=utf-8
must not render as HTML
```

---

## TeX

```text
valid .tex -> allow
TeX commands -> stored as text
no compilation
preview content type -> text/plain; charset=utf-8
```

---

## Source

Para cada extensión admitida debe existir al menos cobertura representativa que demuestre:

```text
allowlisted extension
valid UTF-8
canonical file_kind = source
canonical content_type = text/plain
```

Además:

```text
.py + application/octet-stream client MIME
-> may be accepted when content validation succeeds
```

---

# 60. Pruebas de allowlist

Como mínimo:

```text
.html -> reject
.svg -> reject
.zip -> reject
.exe -> reject
.docx -> reject
.ipynb -> reject
unknown extension -> reject
```

La implementación debe demostrar que una extensión desconocida no entra por fallback.

---

# 61. Pruebas de nombres

Deben existir casos para:

```text
normal filename -> allow
empty filename -> reject
path separators -> reject
control characters -> reject
CR/LF -> reject
header injection attempt -> reject
outer whitespace -> trim
filename empty after trim -> reject
path/traversal attempt -> reject
otherwise safe filename -> preserve
```

---

# 62. Pruebas de bytes originales

Debe demostrarse que:

```text
UTF-8 BOM upload
→ stored/hash bytes preserve BOM
```

y:

```text
CRLF upload
→ stored/hash bytes preserve CRLF
```

La aplicación no debe recalcular hash sobre una representación textual normalizada.

---

# 63. Pruebas de storage layout

Como mínimo:

```text
legacy_pdf_v1
-> resources/<resource>/<file>.pdf
```

```text
generic_v2
-> resources/<resource>/<file>
```

y:

```text
new PDF using generic_v2
-> key without .pdf
```

La resolución legacy y genérica debe coexistir.

---

# 64. Pruebas de presentación HTTP

Debe comprobarse:

```text
PDF preview
-> application/pdf
-> inline
-> nosniff
```

```text
PNG preview
-> image/png
-> inline
-> nosniff
```

```text
JPEG preview
-> image/jpeg
-> inline
-> nosniff
```

```text
Markdown/TeX/TXT/source preview
-> text/plain; charset=utf-8
-> nosniff
```

Y:

```text
download
-> attachment
-> safe filename
```

---

# 65. Separación de responsabilidades

Esta política decide:

```text
¿El archivo es admitido?
¿Qué tipo de archivo es?
¿Cómo se valida?
¿Cómo se almacena conceptualmente?
¿Cómo se muestra de manera segura?
```

No decide:

```text
¿Quién puede acceder?
```

Eso pertenece a:

```text
docs/architecture/resource-access-contract.md
```

Tampoco define la atomicidad PostgreSQL/R2 del proceso de upload.

Eso pertenece a:

```text
docs/architecture/resource-upload-contract.md
```

---

# 66. Relación con otros documentos

Este documento debe leerse junto con:

```text
docs/product/v1-product-contract.md
```

para el alcance funcional del producto;

```text
docs/architecture/resource-access-contract.md
```

para autorización y audiencias;

```text
docs/architecture/resource-upload-contract.md
```

para atomicidad, compensación y estados del upload;

```text
docs/adr/0011-resource-files-access-and-external-identities.md
```

para la decisión arquitectónica global.

---

# 67. No objetivos v1

Esta política no introduce:

- múltiples archivos por recurso;
- directorios;
- ZIP de proyectos;
- antivirus server-side;
- ejecución sandboxed;
- compilación de código;
- compilación LaTeX;
- syntax highlighting obligatorio;
- Markdown rendering;
- HTML rendering;
- SVG;
- thumbnails;
- conversión de imágenes;
- transcodificación;
- OCR;
- normalización automática de archivos;
- conversión automática entre formatos;
- límites de dimensiones de imagen;
- URLs públicas directas de R2.

Estas capacidades requieren decisiones futuras explícitas si llegan a ser necesarias.

---

# 68. Regla de implementación

Codex y cualquier implementación futura deben tratar esta política como una allowlist cerrada.

No deben ampliar:

- extensiones;
- `file_kind`;
- media types;
- límites;
- estrategias de preview;
- layouts de storage;

por conveniencia de implementación.

Toda ampliación requiere primero una modificación explícita y aceptada de este contrato.
