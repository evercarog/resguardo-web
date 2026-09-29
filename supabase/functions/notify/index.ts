// Notificaciones push de Resguardo.
//
// - Sin cuerpo (lo llama pg_cron cada 10 min): calcula los avisos actuales y
//   notifica solo los que empeoran o se recuperan desde el último aviso. Es
//   idempotente: llamarla de más no repite notificaciones.
// - { test: true } con la sesión del usuario (2FA completada): envía una
//   notificación de prueba a sus dispositivos.
//
// Secretos necesarios: VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT.
import { createClient, type SupabaseClient } from 'npm:@supabase/supabase-js@2';
import webpush from 'npm:web-push@3.6.7';

const CORS = {
	'Access-Control-Allow-Origin': '*',
	'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
	'Access-Control-Allow-Methods': 'POST, OPTIONS'
};

/** Cuanto mayor, peor. Se notifica al empeorar y al volver a "ok". */
const SEVERITY: Record<string, number> = { ok: 0, late: 1, offline: 2, overdue: 2, failed: 3 };

type Payload = { title: string; body: string; url: string; tag?: string };

function json(data: unknown, status = 200) {
	return new Response(JSON.stringify(data), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });
}

async function sendTo(admin: SupabaseClient, owner: string, payload: Payload) {
	const { data: subs } = await admin.from('push_subscriptions').select('id, endpoint, p256dh, auth').eq('owner', owner);
	let sent = 0;
	for (const s of subs ?? []) {
		try {
			await webpush.sendNotification(
				{ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
				JSON.stringify(payload),
				{ TTL: 6 * 3600, urgency: 'high' }
			);
			sent++;
		} catch (e) {
			const status = (e as { statusCode?: number }).statusCode;
			// La suscripción ya no existe (app desinstalada, permiso retirado…).
			if (status === 404 || status === 410) await admin.from('push_subscriptions').delete().eq('id', s.id);
			else console.error('push', status, (e as Error).message);
		}
	}
	return sent;
}

/** Nivel de sesión del JWT (aal2 = verificación en dos pasos completada). */
function aalOf(jwt: string) {
	try {
		const payload = JSON.parse(atob(jwt.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')));
		return payload.aal as string | undefined;
	} catch {
		return undefined;
	}
}

Deno.serve(async (req) => {
	if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });

	const admin = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, {
		auth: { persistSession: false }
	});
	webpush.setVapidDetails(
		Deno.env.get('VAPID_SUBJECT')!,
		Deno.env.get('VAPID_PUBLIC_KEY')!,
		Deno.env.get('VAPID_PRIVATE_KEY')!
	);

	let body: { test?: boolean } = {};
	try {
		body = await req.json();
	} catch {
		/* sin cuerpo */
	}

	// Notificación de prueba para el usuario que la pide.
	if (body.test) {
		const jwt = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
		const { data } = await admin.auth.getUser(jwt);
		if (!data.user || aalOf(jwt) !== 'aal2') return json({ error: 'No autorizado' }, 401);
		const sent = await sendTo(admin, data.user.id, {
			title: 'Resguardo',
			body: 'Las notificaciones funcionan en este dispositivo.',
			url: '/',
			tag: 'prueba'
		});
		return json({ sent });
	}

	// Revisión periódica.
	const [{ data: alerts, error: e1 }, { data: states, error: e2 }, { data: subs, error: e3 }] = await Promise.all([
		admin.rpc('current_alerts'),
		admin.from('alert_state').select('owner, alert_key, level'),
		admin.from('push_subscriptions').select('owner')
	]);
	if (e1 || e2 || e3) return json({ error: (e1 ?? e2 ?? e3)!.message }, 500);
	// Solo quien tiene algún dispositivo suscrito: así, al activar las
	// notificaciones, llegan también los avisos que ya estaban pendientes.
	const subscribed = new Set((subs ?? []).map((s) => s.owner as string));

	const prev = new Map<string, string>();
	for (const s of states ?? []) prev.set(`${s.owner}|${s.alert_key}`, s.level);

	let notified = 0;
	const seen = new Set<string>();
	for (const a of alerts ?? []) {
		if (!subscribed.has(a.owner)) continue;
		const key = `${a.owner}|${a.alert_key}`;
		seen.add(key);
		const before = prev.get(key) ?? 'ok';
		if (a.level === before) continue;

		if (a.level === 'ok') {
			// Se recuperó: se avisa y se olvida.
			notified += await sendTo(admin, a.owner, { title: a.title, body: a.body, url: a.url, tag: a.alert_key });
			await admin.from('alert_state').delete().eq('owner', a.owner).eq('alert_key', a.alert_key);
		} else {
			if ((SEVERITY[a.level] ?? 1) > (SEVERITY[before] ?? 0)) {
				notified += await sendTo(admin, a.owner, { title: a.title, body: a.body, url: a.url, tag: a.alert_key });
			}
			await admin
				.from('alert_state')
				.upsert({ owner: a.owner, alert_key: a.alert_key, level: a.level, notified_at: new Date().toISOString() });
		}
	}

	// Avisos de repositorios o equipos que ya no existen.
	for (const s of states ?? []) {
		if (subscribed.has(s.owner) && !seen.has(`${s.owner}|${s.alert_key}`)) {
			await admin.from('alert_state').delete().eq('owner', s.owner).eq('alert_key', s.alert_key);
		}
	}

	return json({ alerts: alerts?.length ?? 0, notified });
});
