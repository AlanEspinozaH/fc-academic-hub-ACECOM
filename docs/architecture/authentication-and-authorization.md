# Autenticación y autorización

## Estado

Baseline implementado: **3A / 3B / 4A**

Evolución de producto y arquitectura: **aceptada para Stage 4C**

Implementación de las nuevas reglas de identidad externa, `privileged` y entitlements: **pendiente**

Este documento describe tanto la arquitectura de autenticación ya existente como su evolución aceptada para FC Academic Hub v1.

Cuando una sección describe Stage 4C como objetivo, no debe interpretarse como comportamiento ya implementado.

---

## Propósito

FC Academic Hub separa explícitamente:

```text
autenticación
```

de:

```text
autorización
```

Autenticación responde:

> ¿Quién es este actor?

Autorización responde:

> Dada esa identidad y el recurso solicitado, ¿qué puede hacer?

La autenticación se apoya en Supabase Auth y Google OAuth.

La autorización de aplicación permanece bajo control de PostgreSQL mediante perfiles, estados de cuenta, identidad institucional o externa, roles, entitlements, RLS y funciones controladas.

El navegador nunca es la autoridad sobre roles, privilegios o acceso a recursos.

---

# 1. Separación de responsabilidades

## Supabase Auth

`auth.users` representa las identidades autenticadas gestionadas por Supabase.

Supabase Auth es responsable de aspectos como:

* autenticación con Google;
* sesiones;
* intercambio OAuth;
* identidad autenticada.

No determina por sí mismo:

* roles de aplicación;
* audiencia de recursos;
* permisos de moderación;
* entitlements;
* autorización de archivos.

---

## PostgreSQL

PostgreSQL es la autoridad de autorización de la aplicación.

Debe resolver información como:

```text
user_id
identity_kind
account_status
roles
entitlements
resource ownership
review_status
visibility
rights_status
```

y aplicar las correspondientes políticas RLS y funciones de autorización.

---

## Astro SSR / Worker

El runtime server-side:

* valida la identidad de la request;
* utiliza un cliente Supabase asociado a esa request;
* delega autorización de datos en PostgreSQL;
* ejecuta los flujos server-side permitidos;
* nunca confía en roles o grants proporcionados por el navegador.

`Astro.locals.auth` proporciona contexto de autenticación.

No constituye por sí solo una decisión de autorización.

---

# 2. Decisiones de seguridad vigentes

La configuración pública de Supabase se limita a:

```text
PUBLIC_SUPABASE_URL
PUBLIC_SUPABASE_PUBLISHABLE_KEY
```

La publishable key puede estar disponible en el navegador.

No constituye una credencial administrativa y su seguridad depende de:

* Supabase Auth;
* grants PostgreSQL;
* RLS;
* funciones controladas;
* autorización server-side.

Las claves secretas no deben formar parte del runtime normal de Astro.

---

## `service_role`

FC Academic Hub no utiliza:

```text
service_role
```

en el runtime normal de Astro.

La `service_role` omite RLS y por tanto no debe utilizarse como solución para simplificar autorización server-side.

Las operaciones normales del producto deben funcionar mediante:

* identidad del usuario;
* RLS;
* RPC controladas;
* privilegios mínimos.

---

## Datos controlados por navegador

No se confía como autoridad en:

```text
localStorage
form fields
query parameters
client JSON
client headers
OAuth metadata controlable por cliente
```

para determinar roles o permisos.

Por ejemplo, una request que incluya:

```text
role = administrator
```

no obtiene ningún privilegio.

---

# 3. Funciones `SECURITY DEFINER`

Cuando una función PostgreSQL requiera `SECURITY DEFINER`, debe mantener las garantías de seguridad existentes:

* `search_path` controlado;
* nombres SQL completamente calificados;
* sin SQL dinámico innecesario;
* `EXECUTE` concedido únicamente a las firmas y roles requeridos;
* validación del actor mediante `auth.uid()`;
* mínimo privilegio.

Una función `SECURITY DEFINER` no debe convertirse en una manera indirecta de saltarse RLS sin una política explícita.

---

# 4. Custom JWT claims

FC Academic Hub v1 no utiliza custom JWT claims como fuente autoritativa de roles o entitlements.

No se duplican automáticamente en el JWT:

```text
roles
privileged_material.read
identity_kind
```

La razón es evitar problemas de:

* revocación tardía;
* claims obsoletos;
* invalidación compleja;
* divergencia entre token y PostgreSQL.

Las decisiones sensibles continúan consultando información autoritativa en PostgreSQL.

Si una evolución futura requiere claims por rendimiento, deberá definir mediante ADR:

* qué datos se replican;
* tiempo máximo de obsolescencia;
* revocación;
* invalidación;
* riesgos aceptados.

---

# 5. Flujo Google OAuth existente

## Sign-in

```text
GET /auth/sign-in
```

muestra la entrada a Google OAuth.

Los destinos posteriores a autenticación deben limitarse a destinos internos válidos.

No se aceptan redirects externos arbitrarios.

---

## Inicio OAuth

```text
POST /auth/google
```

inicia el flujo con Google mediante Supabase Auth.

Debe:

* validar `Origin` cuando corresponda;
* evitar redirects abiertos;
* utilizar el cliente Supabase de la request;
* construir únicamente callbacks internos controlados;
* no aceptar tokens proporcionados manualmente por el cliente.

La aplicación no necesita solicitar acceso a:

* Gmail;
* Google Drive;
* Google Calendar;
* otras APIs de Google.

Google se utiliza como proveedor de identidad.

---

## Callback

```text
GET /auth/callback
```

completa el intercambio OAuth/PKCE.

Después del intercambio, la identidad debe validarse mediante una operación confiable equivalente a:

```text
auth.getUser()
```

y no mediante datos de sesión no verificados como autoridad de identidad.

Los errores del proveedor no deben reflejarse directamente al navegador sin normalización.

Los códigos OAuth y datos sensibles no deben permanecer en la URL final.

---

## Sign-out

```text
POST /auth/sign-out
```

realiza logout.

Debe conservar protección frente a solicitudes cross-origin cuando corresponda y redirigir únicamente a destinos internos válidos.

---

# 6. Tokens del proveedor Google

Supabase puede incluir:

```text
provider_token
provider_refresh_token
```

en determinadas respuestas OAuth.

FC Academic Hub no utiliza esos tokens.

La aplicación conserva el mecanismo de redacción previo a persistencia para evitar almacenarlos dentro de la sesión procesada por `auth-js`.

Los tokens propios de Supabase necesarios para la sesión se mantienen.

No deben persistirse tokens de Google innecesarios.

---

# 7. Clientes Supabase SSR

La arquitectura mantiene clientes separados para navegador y servidor.

El cliente server-side se crea por request.

No se deben ejecutar durante import:

* login;
* logout;
* `getUser`;
* consultas;
* decisiones de autorización.

El middleware es responsable de validar la identidad durante una request real.

---

# 8. Contexto SSR

`Astro.locals.auth` conserva un contexto mínimo.

Conceptualmente contiene:

```text
status
user
supabase
```

Los estados pueden incluir:

```text
unconfigured
anonymous
authenticated
error
```

La identidad expuesta al contexto SSR debe mantenerse mínima.

No debe incluir automáticamente:

* tokens;
* roles;
* entitlements;
* `storage_key`;
* credenciales;
* sesión OAuth completa.

---

# 9. `Astro.locals.auth` no autoriza

La presencia de:

```text
status = authenticated
```

solo demuestra que existe una identidad autenticada válida.

No significa automáticamente:

```text
can read restricted
can read privileged
can upload
can moderate
can administer
```

Las capacidades dependen de datos autoritativos adicionales.

Por ejemplo:

```text
authenticated
+
external_authorized
+
sin entitlement
```

puede acceder a contenido público, no puede acceder a `restricted` y solo puede acceder a `privileged` si posee `privileged_material.read`.

---

# 10. Baseline actual de Auth/profiles

El diseño existente utiliza:

```text
auth.users
```

como identidad gestionada por Supabase y:

```text
public.profiles
```

para información de aplicación.

El baseline actual conserva información como:

```text
user_id
email
display_name
account_status
timestamps
```

Los estados de cuenta son:

```text
active
suspended
disabled
```

El comportamiento actualmente implementado fue diseñado alrededor de dominios institucionales permitidos.

Stage 4C debe evolucionar este modelo para admitir también identidades externas explícitamente preautorizadas.

---

# 11. Evolución aceptada 4C: clases de identidad

FC Academic Hub debe distinguir conceptualmente:

```text
institutional
external_authorized
```

Esta propiedad se denomina en este contrato:

```text
identity_kind
```

El nombre físico exacto de la columna o enum puede establecerse durante la implementación, pero el sistema debe representar de manera persistente esta diferencia.

---

## `institutional`

Representa una identidad reconocida como miembro de la comunidad institucional ordinaria.

Una identidad:

```text
active
+
institutional
```

puede acceder a recursos:

```text
approved + restricted
```

sin requerir un rol editorial.

---

## `external_authorized`

Representa una identidad externa que la Facultad decidió admitir expresamente.

Por ejemplo, puede corresponder a un colaborador que utilice:

```text
persona@gmail.com
```

La identidad externa no se convierte en institucional.

En v1, `external_authorized` es una identidad exclusivamente lectora.

No puede recibir roles internos:

```text
student
contributor
reviewer
moderator
administrator
```

Puede recibir el entitlement:

```text
privileged_material.read
```

cuando Administrator lo conceda explícitamente.

Sin dicho entitlement, una identidad externa activa conserva únicamente las capacidades públicas disponibles para cualquier usuario.

---

# 12. Email no es autorización runtime

El email participa en:

* autenticación;
* admisión;
* mantenimiento de identidad.

No debe ser el mecanismo runtime de autorización.

No se permiten decisiones de acceso equivalentes a:

```text
if email.endsWith("@universidad.edu")
```

o:

```text
if email === "persona@gmail.com"
```

dentro de la política ordinaria de lectura de recursos.

Una vez admitida la identidad, las decisiones runtime deben utilizar propiedades controladas por el sistema, como:

```text
user_id
identity_kind
account_status
roles
entitlements
```

---

# 13. Admisión institucional

Una identidad institucional puede ser admitida mediante la política de dominios institucionales permitidos.

Conceptualmente:

```text
email pertenece a dominio institucional autorizado
        ↓
identity_kind = institutional
```

La implementación exacta puede conservar los mecanismos de validación PostgreSQL existentes adaptados al nuevo contrato.

---

# 14. Admisión externa

Una dirección externa no puede autenticarse simplemente porque Google OAuth la considere válida.

La regla v1 es:

```text
institutional allowed domain
OR
exact external preauthorization
```

Por tanto:

```text
random-person@gmail.com
```

debe ser rechazado si no existe una preautorización correspondiente.

---

# 15. Preautorización externa

La preautorización externa responde exclusivamente:

> ¿Está permitida esta identidad externa para formar una cuenta en FC Academic Hub?

Conceptualmente puede conservar:

```text
normalized_email
status
authorized_by
authorized_at
revoked_by
revoked_at
reason
```

La estructura SQL exacta se define durante implementación.

La preautorización debe ser:

* explícita;
* auditable;
* revocable;
* limitada al email exacto autorizado.

No existe una regla general:

```text
@gmail.com
→ allowed
```

La preautorización controla únicamente la admisión.

Revocarla:

```text
antes de materializar la cuenta
-> impide la admisión futura
```

Si la cuenta ya existe:

```text
revocar preautorización
-> NO suspende ni deshabilita automáticamente la cuenta
```

El acceso de una cuenta ya materializada se controla mediante:

```text
account_status
entitlements
```

Para retirar acceso privilegiado debe revocarse `privileged_material.read`.

Cuando corresponda retirar también las capacidades autenticadas de la cuenta, Administrator debe cambiar explícitamente su estado a `suspended` o `disabled`.

---

# 16. Fuente confiable del email

La admisión no debe confiar en un email arbitrario proporcionado por:

* formulario;
* query parameter;
* JSON del navegador.

La identidad debe proceder del proveedor/Auth validado por Supabase.

La aplicación debe aplicar la política de admisión sobre la identidad autenticada confiable y normalizada.

---

# 17. Admisión no equivale a privilegio

Estas dos operaciones deben permanecer separadas:

```text
admitir una identidad externa
```

y:

```text
conceder privileged_material.read
```

Por ejemplo:

```text
external_authorized
+
active
+
sin entitlement
```

es válido.

Ese usuario puede autenticarse, pero sigue sin poder acceder a:

```text
restricted
privileged
```

como audiencia especial.

---

# 18. Roles y entitlements

Stage 4C establece una separación explícita.

## Roles

Los roles representan capacidades dentro del workflow:

```text
student
contributor
reviewer
moderator
administrator
```
En v1, todos los roles internos requieren:

```text
identity_kind = institutional
account_status = active
```

Una identidad:

```text
external_authorized
```

no puede recibir ninguno de estos roles.

La admisión externa existe únicamente para permitir lectura autenticada y, cuando exista concesión explícita, acceso mediante `privileged_material.read`.

Ejemplos:

```text
contributor
→ crear y enviar recursos
```

```text
moderator
→ revisar y publicar
```

```text
administrator
→ administrar cuentas, roles y privilegios
```

---

## Entitlements

Los entitlements representan capacidades especiales independientes de roles editoriales.

El entitlement v1 es:

```text
privileged_material.read
```

Su único propósito es formar parte de la audiencia:

```text
approved + privileged
```

No concede:

* Contributor;
* Reviewer;
* Moderator;
* Administrator;
* capacidad de upload;
* capacidad de publicación.

---

# 19. Privileged y correo externo

Un usuario puede tener:

```text
identity_kind = external_authorized
account_status = active
privileged_material.read
```

y acceder a:

```text
approved + privileged
```

sin convertirse en usuario institucional.

Ese mismo usuario no obtiene automáticamente:

```text
approved + restricted
```

porque `restricted` representa la audiencia institucional ordinaria.

---

# 20. Privileged e identidad institucional

Una identidad institucional también puede recibir:

```text
privileged_material.read
```

En ese caso:

```text
approved + public      -> permitido
approved + restricted  -> permitido
approved + privileged  -> permitido
```

si la cuenta permanece activa.

---

# 21. Administración de entitlements

En v1, Administrator es la autoridad que concede y revoca:

```text
privileged_material.read
```

La asignación se realiza a una identidad interna mediante:

```text
user_id
```

y no mediante un email utilizado permanentemente como permiso.

Conceptualmente debe poder auditarse:

```text
user_id
entitlement
granted_by
granted_at
revoked_by
revoked_at
reason
```

La implementación SQL exacta pertenece a Stage 4C.

---

# 22. Roles y entitlements no se derivan automáticamente

La creación de una identidad no asigna automáticamente:

```text
student
contributor
reviewer
moderator
administrator
privileged_material.read
```

salvo que exista una política futura aceptada que disponga lo contrario.

No existe Administrator automático.

No existe Moderator automático.

No existe entitlement privilegiado automático.

Además, una identidad `external_authorized` no puede recibir roles internos posteriormente mediante una concesión administrativa.

Las combinaciones:

```text
external_authorized + student
external_authorized + contributor
external_authorized + reviewer
external_authorized + moderator
external_authorized + administrator
```

son inválidas en v1.

---

# 23. Account status

Los estados continúan siendo:

```text
active
suspended
disabled
```

Los privilegios autenticados requieren una cuenta:

```text
active
```

---

## `active`

Puede utilizar todas las capacidades que le concedan:

* identidad;
* roles;
* entitlements;
* ownership;
* políticas de recursos.

---

## `suspended`

Pierde:

* acceso `restricted`;
* acceso `privileged`;
* roles editoriales;
* privilegios institucionales;
* capacidades de contribución y moderación.

Conserva únicamente el contenido disponible públicamente.

---

## `disabled`

Tiene el mismo baseline de lectura pública que un visitante anónimo.

No obtiene capacidades autenticadas internas.

---

# 24. Público no depende de la sesión

Stage 4C corrige una inconsistencia del modelo anterior.

El acceso:

```text
approved + public
```

es universal cuando los derechos permiten su publicación.

Por tanto, debe estar disponible para:

```text
anonymous
active
suspended
disabled
```

La presencia de una sesión suspendida o deshabilitada no puede producir menos acceso a contenido público que cerrar sesión.

---

# 25. Restricted

El acceso:

```text
approved + restricted
```

requiere:

```text
authenticated
+
active
+
identity_kind = institutional
```

No requiere:

```text
student role
```

como condición fundamental.

El rol `student` puede conservarse por compatibilidad o futuras funciones, pero la pertenencia a la audiencia `restricted` proviene de identidad institucional activa.

---

# 26. Privileged

El acceso:

```text
approved + privileged
```

requiere:

```text
authenticated
+
active
+
privileged_material.read
```

`identity_kind` puede ser:

```text
institutional
```

o:

```text
external_authorized
```

El entitlement nunca permite saltarse:

```text
draft
pending
rejected
```

---

# 27. Recursos en workflow

Las audiencias:

```text
public
restricted
privileged
```

solo funcionan como audiencias finales cuando:

```text
review_status = approved
```

Por ejemplo:

```text
pending + public
```

no es públicamente visible.

Y:

```text
pending + privileged
```

no es visible para usuarios privilegiados ordinarios.

---

# 28. Moderator

Moderator representa autoridad editorial ordinaria.

Puede intervenir en recursos:

```text
pending
```

según el contrato de acceso.

No debe poder acceder a:

```text
draft
rejected
```

ajenos únicamente porque posea el rol Moderator.

Tampoco gestiona entitlements permanentes ni admisión externa.

---

# 29. Administrator

Administrator representa autoridad administrativa.

Puede:

* gestionar roles;
* gestionar Moderators;
* conceder/revocar entitlements;
* gestionar admisión externa;
* suspender/deshabilitar cuentas;
* responder a incidentes;
* realizar acceso administrativo excepcional según el contrato de recursos.

Administrator no sustituye al Moderator como flujo editorial ordinario.

---

# 30. Cambio de email

Un cambio de email ordinario no debe convertirse en un mecanismo de reclasificación automática de identidad.

Por ejemplo:

```text
institutional
+
usuario@facultad.edu
```

no debe transformarse automáticamente en:

```text
external_authorized
```

porque el email cambie a Gmail.

Tampoco el proceso inverso debe producirse automáticamente.

---

# 31. Cambio de `identity_kind`

Los cambios entre:

```text
institutional
```

y:

```text
external_authorized
```

requieren una operación administrativa explícita.

La operación debe ser:

* autorizada;
* auditada;
* coherente con la identidad actualmente validada;
* incapaz de convertirse en una elevación automática de privilegios.

---

# 32. Account linking

FC Academic Hub v1 no implementa linking complejo de múltiples identidades.

No se asume automáticamente que:

```text
persona@gmail.com
```

y:

```text
persona@universidad.edu
```

pertenecen a la misma cuenta.

En v1 se utiliza una identidad principal por cuenta.

Una futura capacidad de linking debe diseñarse explícitamente debido a los riesgos de:

* account takeover;
* duplicación de cuentas;
* transferencia de roles;
* transferencia de entitlements;
* recuperación de cuenta.

---

# 33. Recursos académicos: baseline previo

El modelo introducido en 4A estableció:

```text
public.academic_resources
public.resource_files
private.resource_storage_objects
public.resource_review_events
```

y autorización basada en:

* perfiles activos;
* roles;
* ownership;
* `review_status`;
* `visibility`.

Ese baseline se conserva históricamente.

Stage 4C modifica determinadas reglas de acceso sin eliminar la separación estructural introducida por 4A.

---

# 34. Recursos académicos: evolución Stage 4C

La autorización objetivo debe considerar conjuntamente:

```text
actor
account_status
identity_kind
roles
entitlements
ownership
review_status
visibility
rights_status
```

PostgreSQL sigue siendo la fuente autoritativa.

La lógica no debe duplicarse de forma divergente en TypeScript.

---

# 35. Relación con RLS

Las políticas RLS deben hacer cumplir el contrato definido en:

```text
docs/architecture/resource-access-contract.md
```

Especialmente:

```text
approved + public
→ universal
```

```text
approved + restricted
→ active institutional
```

```text
approved + privileged
→ active + privileged_material.read
```

y las reglas específicas del workflow para:

```text
draft
pending
rejected
```

---

# 36. Autorización de archivos

La autorización de un archivo utiliza la autorización del recurso correspondiente.

Autenticarse no concede automáticamente acceso al archivo.

La secuencia conceptual es:

```text
request
   ↓
authenticated/anonymous identity
   ↓
PostgreSQL authorization
   ↓
accessible resource/file metadata?
   │
   ├── no -> deny
   │
   └── yes
         ↓
      server-side storage retrieval
```

El storage nunca decide identidad, roles o audiencia.

---

# 37. `storage_key`

La autenticación y autorización nunca necesitan revelar al cliente:

```text
storage_key
```

La clave de almacenamiento pertenece a infraestructura privada.

No debe convertirse en:

* claim;
* cookie;
* localStorage;
* respuesta de autorización;
* identificador de recurso público.

---

# 38. Auditoría

Las operaciones sensibles de identidad y autorización deben poder auditarse.

Como mínimo:

* grant de rol;
* revoke de rol;
* grant de entitlement;
* revoke de entitlement;
* preautorización externa;
* revocación de preautorización;
* cambio administrativo de `identity_kind`;
* suspensión;
* desactivación;
* reactivación cuando corresponda.

El actor administrativo debe derivarse de la sesión autorizada y no ser proporcionado libremente por el cliente.

---

# 39. Invariantes normativas de Auth

## AA-01 — Auth is identity, not authorization

Una sesión autenticada no concede por sí sola permisos sobre recursos.

---

## AA-02 — PostgreSQL authority

Roles, account status, identity kind y entitlements se resuelven mediante datos autoritativos de aplicación.

---

## AA-03 — No client roles

Los roles enviados por navegador nunca se consideran autoridad.

---

## AA-04 — No service role runtime

Astro no utiliza `service_role` para las operaciones normales de usuario.

---

## AA-05 — Institutional admission

Una identidad institucional debe cumplir la política institucional de admisión.

---

## AA-06 — Explicit external admission

Una identidad externa requiere preautorización explícita.

---

## AA-07 — No generic Gmail admission

No existe una regla que permita automáticamente cualquier Gmail.

---

## AA-08 — Admission is not entitlement

Admitir una identidad externa no concede `privileged_material.read`.

---

## AA-09 — Authorization by user identity

Los roles y entitlements se asocian al `user_id`, no a comparaciones runtime de email.

---

## AA-10 — Stable identity classification

La autorización runtime utiliza una clasificación persistente equivalente a `identity_kind`.

---

## AA-11 — Explicit identity-kind transitions

Cambiar entre institucional y externo autorizado requiere una operación administrativa explícita.

---

## AA-12 — Restricted identity

Acceso `restricted` requiere cuenta activa e identidad institucional.

---

## AA-13 — Privileged entitlement

Acceso `privileged` requiere cuenta activa y `privileged_material.read`.

---

## AA-14 — Privileged does not imply restricted

Una identidad externa privilegiada no obtiene acceso `restricted`.

---

## AA-15 — Public baseline

Las cuentas suspended/disabled conservan únicamente el acceso público disponible para anonymous.

---

## AA-16 — No workflow bypass

Identidad, rol o entitlement nunca convierten un recurso no aprobado en públicamente consumible.

---

## AA-17 — Administrator manages grants

Administrator gestiona la admisión externa y los entitlements en v1.

---

## AA-18 — No automatic account linking

V1 no fusiona identidades únicamente por coincidencia de nombre, email alternativo o dominio.

## AA-19 — External identities are reader-only

Una identidad `external_authorized` no puede poseer roles internos en v1.

Su única capacidad autenticada adicional puede provenir de entitlements explícitos como `privileged_material.read`.

---

## AA-20 — External preauthorization lifecycle

La preautorización externa controla admisión, no el estado de una cuenta ya materializada.

Revocar una preautorización impide admisiones futuras, pero no suspende automáticamente una cuenta existente.

---

# 40. Pruebas normativas requeridas

Stage 4C debe demostrar como mínimo los siguientes casos.

## Admisión institucional

```text
allowed institutional identity
-> admitted as institutional
```

```text
non-allowed institutional domain
-> rejected
```

---

## Admisión externa

```text
random external email
-> rejected
```

```text
preauthorized external email
-> admitted as external_authorized
```

```text
revoked external preauthorization
+ account not yet materialized
-> admission rejected
```

```text
revoked external preauthorization
+ existing active account
-> account remains active until explicitly suspended/disabled
```

---

## Sin privilegio automático

```text
new institutional identity
-> no automatic editorial role
```

```text
new external_authorized identity
-> no automatic editorial role
-> no automatic privileged_material.read
```

---

## Restricted

```text
active institutional
+ approved/restricted
-> allow
```

```text
active external_authorized
+ approved/restricted
-> deny
```

```text
external_authorized + privileged_material.read
+ approved/restricted
-> deny
```

---

## Privileged

```text
active institutional without entitlement
+ approved/privileged
-> deny
```

```text
active institutional with entitlement
+ approved/privileged
-> allow
```

```text
active external_authorized with entitlement
+ approved/privileged
-> allow
```

---

## Suspended

```text
suspended
+ approved/public
-> allow
```

```text
suspended
+ approved/restricted
-> deny
```

```text
suspended + entitlement
+ approved/privileged
-> deny
```

---

## Revocation

```text
active external + entitlement
-> privileged allowed
```

después:

```text
entitlement revoked
-> privileged denied
```

sin necesitar cambiar su email o eliminar su cuenta.

---

## Role/entitlement orthogonality

```text
external_authorized
+ privileged_material.read
+ no editorial roles
```

debe poder:

```text
read approved/privileged
```

pero no:

```text
create resource
review pending
approve
manage users
```

```text
external_authorized + student
-> invalid

external_authorized + contributor
-> invalid

external_authorized + reviewer
-> invalid

external_authorized + moderator
-> invalid

external_authorized + administrator
-> invalid

external_authorized + privileged_material.read
-> valid
```

---

# 41. Non-goals v1

Esta arquitectura no introduce:

* registro abierto a cualquier email;
* registro abierto a cualquier Gmail;
* custom JWT claims de autorización;
* autorización por `app_metadata`;
* autorización por `raw_user_meta_data`;
* autorización runtime por dominio de email;
* account linking automático;
* múltiples proveedores asociados automáticamente a una cuenta;
* ACL por recurso;
* múltiples cohortes privileged;
* roles creados automáticamente;
* Moderator automático;
* Administrator automático;
* entitlements automáticos.

---

# 42. Relación con otros documentos

Este documento describe identidad y arquitectura general de autorización.

Las reglas exactas de acceso a recursos viven en:

```text
docs/architecture/resource-access-contract.md
```

Las reglas sobre tipos y tratamiento de archivos viven en:

```text
docs/architecture/resource-file-policy.md
```

Las garantías de subida PostgreSQL/R2 viven en:

```text
docs/architecture/resource-upload-contract.md
```

Las responsabilidades de roles y entitlements se documentan en:

```text
docs/security/role-model.md
```

Las decisiones arquitectónicas de Stage 4C deben registrarse además en el ADR correspondiente.

---

# 43. Entorno local

Supabase local debe permanecer aislado de Internet.

Los comandos locales vigentes para el workflow existente son:

```sh
npx --yes supabase@2.109.1 start
npx --yes supabase@2.109.1 db reset
npx --yes supabase@2.109.1 test db
npx --yes supabase@2.109.1 db lint --local
npx --yes supabase@2.109.1 stop
```

Las operaciones remotas:

```text
supabase login
supabase link
supabase db push
```

o equivalentes no forman parte de una modificación local ordinaria y requieren revisión intencional del proyecto y del cambio a aplicar.

---

# 44. Regla para implementación

Codex y cualquier implementación futura deben distinguir claramente:

```text
current implemented behavior
```

de:

```text
accepted Stage 4C target
```

No deben inventar:

* nuevos tipos de identidad;
* nuevos mecanismos de admisión;
* nuevos roles;
* nuevos entitlements;
* bypasses de account status;
* custom claims;
* account linking;

sin modificar primero los contratos normativos correspondientes.

Cuando Stage 4C implemente una regla de este documento, código, migraciones, RLS, tests y documentación deben converger dentro del mismo cambio.
