# Resguardo Web

Panel web (instalable en el celular como app) con el estado de las copias de
los equipos que tienen [Resguardo](../resguardo) vinculado.

- **SvelteKit** como web estática (SPA): se puede publicar en Vercel, Cloudflare
  Pages o cualquier servidor.
- **Supabase**: base de datos (Postgres), inicio de sesión con verificación en
  dos pasos obligatoria y actualización en tiempo real.

## Seguridad

- La web **nunca** recibe contraseñas de repositorios ni nombres de archivos:
  solo metadatos (fechas, duraciones, tamaños, resultado).
- Toda regla de acceso vive en la base de datos (RLS): cada persona solo ve lo
  suyo y **solo con la verificación en dos pasos completada** (`aal2`).
- Los equipos no son usuarios: solo pueden vincularse con un código de un solo
  uso (15 min) y enviar su informe con un secreto propio, del que la base de
  datos solo guarda la huella SHA-256.
- CSP estricta generada en la compilación (solo el código propio y Supabase).

## Puesta en marcha

1. **Variables**: copia `.env.example` como `.env` con la URL y la clave
   publicable del proyecto (Project Settings → API). Nunca la clave secreta.
2. **Base de datos** (en una terminal con el entorno cargado, ver
   `../herramientas/entorno.ps1`):

   ```bash
   supabase link --project-ref TU_PROJECT_REF
   supabase db push
   ```

3. **Autenticación** (panel de Supabase → Authentication):
   - *Users → Add user*: crea tu usuario (correo y contraseña larga).
   - *Sign In / Providers → Email*: desactiva **Allow new users to sign up**,
     para que nadie más pueda registrarse.
   - *URL Configuration*: pon la URL de la web publicada como *Site URL*.
4. **Desarrollo**: `npm install` y `npm run dev`.
5. **Publicar**: importa el repositorio en Vercel (se detecta `vercel.json`) y
   añade las dos variables `PUBLIC_SUPABASE_*` en *Settings → Environment
   Variables*.

## Estructura

```
supabase/migrations/   Tablas, reglas de acceso (RLS) y funciones
src/lib/supabase.ts    Cliente de Supabase
src/lib/session.svelte.ts  Sesión y verificación en dos pasos
src/lib/data.svelte.ts Datos con actualización en tiempo real
src/lib/status.ts      Cálculo de "al día / con retraso / atrasada"
src/routes/            Estado, Vincular, Clientes, login y 2FA
src/service-worker.ts  App instalable (PWA) que abre al instante
```
