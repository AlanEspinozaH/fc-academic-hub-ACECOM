# Gobierno y continuidad operativa

## Estado

Política operativa aceptada para FC Academic Hub.

Este documento define cómo se asignan y transfieren responsabilidades institucionales alrededor de la plataforma.

No define permisos RLS ni reglas de acceso a recursos.

Las capacidades técnicas de los roles se definen en:

```text
docs/security/role-model.md
```

---

# 1. Separación de responsabilidades

FC Academic Hub distingue tres responsabilidades principales:

```text
autoridad editorial
administración de la aplicación
custodia de infraestructura
```

Estas responsabilidades pueden coincidir temporalmente en una misma persona, pero conceptualmente son independientes.

---

# 2. Gobierno editorial

El Centro de Estudiantes de la Facultad es la referencia institucional para la política editorial, de contenido y derechos de FC Academic Hub.

Su Presidencia vigente puede:

* ejercer directamente la responsabilidad editorial operativa; o
* designar a un miembro institucional de confianza.

La responsabilidad editorial operativa se representa dentro de la aplicación mediante el rol:

```text
moderator
```

El delegado debe mantener:

```text
identity_kind = institutional
account_status = active
```

La existencia de esta designación no modifica las reglas técnicas del rol Moderator.

---

# 3. Gobierno técnico y administrativo

ACECOM es la referencia institucional para la continuidad técnica, seguridad y administración operativa de la plataforma.

Su Presidencia vigente puede:

* ejercer directamente la responsabilidad administrativa; o
* designar a un miembro institucional de confianza.

La responsabilidad administrativa de la aplicación se representa mediante:

```text
administrator
```

El delegado debe mantener:

```text
identity_kind = institutional
account_status = active
```

---

# 4. Infrastructure Custodian

La custodia de infraestructura es una responsabilidad distinta del rol `administrator`.

Puede comprender control operativo sobre:

```text
GitHub
Cloudflare
Supabase
deployment
secrets
configuration
```

La misma persona puede ser simultáneamente:

```text
App Administrator
+
Infrastructure Custodian
```

pero esa coincidencia no constituye una invariante de arquitectura.

La responsabilidad puede separarse posteriormente sin modificar el modelo de autorización de FC Academic Hub.

---

# 5. Transferencia ordinaria

Los cargos institucionales y sus delegaciones cambian con el tiempo.

El software no revoca automáticamente roles en una fecha electoral ni intenta inferir cambios de autoridades.

La transferencia ordinaria debe ser explícita.

Conceptualmente:

```text
nueva autoridad asume
        ↓
define si ejercerá o designará delegado
        ↓
se concede el acceso correspondiente
        ↓
se verifica acceso efectivo
        ↓
se revoca el acceso del responsable anterior
        ↓
se registra la transferencia
```

La transferencia debe evitar periodos innecesarios sin responsables activos.

---

# 6. Consejo de Continuidad

Para recuperación extraordinaria se define un Consejo de Continuidad compuesto por las siguientes funciones institucionales:

1. Presidencia vigente del Centro de Estudiantes;
2. Presidencia vigente de ACECOM;
3. Secretaría/Tesorería del proyecto FC Academic Hub.

La pertenencia corresponde a los cargos o funciones, no a nombres personales permanentes.

---

# 7. Regla de recuperación 2 de 3

Una recuperación extraordinaria o transferencia forzada de control requiere aprobación documentada de:

```text
al menos 2 de los 3 miembros
```

del Consejo de Continuidad.

Esta regla se aplica a situaciones como:

* pérdida de acceso administrativo;
* pérdida de custodia de infraestructura;
* salida inesperada del responsable;
* cuenta administrativa comprometida;
* transferencia anual fallida;
* disputa sobre la custodia técnica;
* imposibilidad de completar el relevo ordinario.

---

# 8. Alcance de la regla 2 de 3

La regla de continuidad no forma parte del workflow ordinario de publicación.

No significa:

```text
2 de 3 para aprobar recursos
```

ni:

```text
2 de 3 para conceder cada rol
```

Su finalidad es exclusivamente la recuperación excepcional y la continuidad del control de la plataforma.

---

# 9. Auditoría

Las transferencias relevantes deben dejar evidencia suficiente para conocer:

* responsabilidad transferida;
* responsable anterior;
* responsable nuevo;
* autoridad que aprobó la transferencia;
* fecha;
* razón cuando no sea una transición ordinaria.

Las credenciales y secretos no deben almacenarse dentro del registro de auditoría.

---

# 10. Relación con la arquitectura

Este documento asigna responsabilidades organizacionales.

No redefine:

```text
Moderator
Administrator
roles
entitlements
identity_kind
resource access
```

Las reglas técnicas continúan perteneciendo a:

```text
docs/security/role-model.md
docs/architecture/authentication-and-authorization.md
docs/architecture/resource-access-contract.md
```

La arquitectura debe continuar funcionando aunque en el futuro cambie qué organización ejerce cada responsabilidad.
