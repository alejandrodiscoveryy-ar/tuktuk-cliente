# elTOQUE en Cliente — entrega FASE 1, sin despliegue

## Alcance implementado en la rama

- Franja superior permanente, pequeña, sin cambiar el mapa ni los pasos de reserva.
- Consulta de tasa USD/CUP usando RPC de solo lectura; sondeo de 5 minutos y al reabrir la WebApp.
- Variación respecto de la actualización anterior e información de origen.
- La franja no presenta datos antiguos o fallidos como tasa actual.
- Test de parsing, variación y frescura.

## DEPENDENCIA PENDIENTE (NO ejecutar automáticamente)

La RPC `public.marketplace_public_eltoque_rate()` está propuesta en
`docs/sql/PENDIENTE_marketplace_public_eltoque_rate.sql`.
Debe revisarse y migrarse por el repositorio propietario de las migraciones,
`vrixora-admin-canvas/supabase/migrations`, con autorización separada.
No sustituye las RPC privadas de Conductor y no habilita escrituras.

## FASE 2 — avisos push por cada cambio (NO implementada todavía)

- Consentimiento voluntario, gratuito, reversible, antes de obtener token push.
- Validar navegador/PWA, Firebase Web Push, service worker y alcance `/cliente/tuk/`.
- Registro de suscripción anónima mediante credencial opaca y protección frente a abuso,
  NO usar `push_device_tokens` ligado a `auth.users` para sesiones Cliente.
- Vincular cada alerta a `rate_history_id` único, evitar duplicados, solo cambios de tasa reales.
- Respetar preferencias, caducidad/revocación y eliminación del token.
- No tocar lógica de viajes, facturación, Conductor ni cambios de la tasa original.
- Antes de habilitar en producción: auditoría RLS, verificación de worker, pruebas Android y navegador.

La fase 1 no debe publicarse hasta que RPC y pruebas estén validadas conjuntamente.
