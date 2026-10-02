// Notificaciones push de Resguardo.
//
// - Sin cuerpo (lo llama pg_cron cada 10 min con el secreto "notify_cron" de
//   Vault en la cabecera x-cron-secret): calcula los avisos actuales y
//   notifica solo los que empeoran o se recuperan desde el último aviso. Una
//   sola revisión a la vez (notify_claim), así nunca se repite un aviso.
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

/**
 * Cuanto mayor, peor. Se notifica al empeorar y al volver a "ok".
 * "critical": subida a la nube frenada por un cambio inusual (posible ransomware).
 * "notice": un hecho que se avisa una vez (petición o entrega de un destino
 * compartido); al desaparecer de la lista se olvida sin avisar.
 */
const SEVERITY: Record<string, number> = { ok: 0, notice: 1, late: 1, offline: 2, overdue: 2, failed: 3, critical: 4 };

type Payload = { title: string; body: string; url: string; tag?: string };

function json(data: unknown, status = 200) {
	return new Response(JSON.stringify(data), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });
}

async function sendTo(admin: SupabaseClient, owner: string, payload: Payload) {
	const { data: subs } = await admin.from('push_subscriptions').select('id, endpoint, p256dh, auth').eq('owner', owner);
	// En paralelo y con límite de tiempo: un servicio de push lento no retrasa a los demás.
	const results = await Promise.allSettled(
		(subs ?? []).map((s) =>
			webpush.sendNotification(
				{ endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
				JSON.stringify(payload),
				{ TTL: 6 * 3600, urgency: 'high', timeout: 10_000 }
			)
		)
	);
	let sent = 0;
	for (const [i, r] of results.entries()) {
		if (r.status === 'fulfilled') {
			sent++;
			continue;
		}
		const status = (r.reason as { statusCode?: number }).statusCode;
		// La suscripción ya no existe (app desinstalada, permiso retirado…).
		if (status === 404 || status === 410) await admin.from('push_subscriptions').delete().eq('id', subs![i].id);
		else console.error('push', status, (r.reason as Error).message);
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

	// Revisión periódica: solo pg_cron (con el secreto de Vault).
	const cronSecret = req.headers.get('x-cron-secret') ?? '';
	const { data: ok } = cronSecret.length >= 32 ? await admin.rpc('notify_cron_ok', { p_secret: cronSecret }) : { data: false };
	if (!ok) return json({ error: 'No autorizado' }, 401);
	const { data: claimed } = await admin.rpc('notify_claim');
	if (!claimed) return json({ skipped: 'otra revisión en curso' });
	try {
		return await periodic(admin);
	} finally {
		await admin.rpc('notify_release');
	}
});

async function periodic(admin: SupabaseClient) {
	const [{ data: alerts, error: e1 }, { data: states, error: e2 }, { data: subs, error: e3 }] = await Promise.all([
		admin.rpc('current_alerts'),
		admin.from('alert_state').select('owner, alert_key, level'),
		admin.from('push_subscriptions').select('owner')
	]);
	if (e1 || e2 || e3) {
		console.error('notify', (e1 ?? e2 ?? e3)!.message);
		return json({ error: 'Error interno' }, 500);
	}
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

	// Avisos de repositorios o equipos que ya no existen (el resumen semanal
	// también se anota aquí y no es un aviso: se conserva).
	for (const s of states ?? []) {
		if (s.alert_key.startsWith('summary:')) continue;
		if (subscribed.has(s.owner) && !seen.has(`${s.owner}|${s.alert_key}`)) {
			await admin.from('alert_state').delete().eq('owner', s.owner).eq('alert_key', s.alert_key);
		}
	}

	notified += await weeklySummary(admin, subscribed, alerts ?? [], states ?? []);
	return json({ alerts: alerts?.length ?? 0, notified });
}

/** Lunes a partir de las 8:00 (Colombia, UTC−5): resumen de la semana, una vez por semana. */
async function weeklySummary(
	admin: SupabaseClient,
	subscribed: Set<string>,
	alerts: { owner: string; alert_key: string; level: string }[],
	states: { owner: string; alert_key: string; level: string }[]
) {
	const now = new Date();
	const bogota = new Date(now.getTime() - 5 * 3_600_000);
	if (bogota.getUTCDay() !== 1 || bogota.getUTCHours() < 8) return 0;
	// Semana: la fecha del lunes (así se envía una sola vez).
	const week = `summary:${bogota.toISOString().slice(0, 10)}`;
	const since = new Date(now.getTime() - 7 * 24 * 3_600_000).toISOString();
	const paused = await pausedByOwner(admin, now);
	const weak = await badProtectionByOwner(admin);
	let sent = 0;
	for (const owner of subscribed) {
		if (states.some((s) => s.owner === owner && s.alert_key === week)) continue;
		// Los destinos en pausa no están en los avisos (salvo si fallaron): no cuentan como al día ni con retraso.
		const mine = alerts.filter((a) => a.owner === owner && a.alert_key.startsWith('repo:'));
		const late = mine.filter((a) => a.level === 'late' || a.level === 'overdue').length;
		const failed = mine.filter((a) => a.level === 'failed').length;
		const ok = mine.length - late - failed;
		const onPause = paused.get(owner) ?? 0;
		const held = alerts.filter((a) => a.owner === owner && a.alert_key.startsWith('hold:') && a.level === 'critical').length;
		const { count } = await admin
			.from('snapshots')
			.select('snapshot_id', { count: 'exact', head: true })
			.eq('owner', owner)
			.gte('time', since);
		// Copias con «Solo guardar si hay cambios» que no encontraron nada nuevo:
		// no crean versión, pero la copia se hizo. Si falla la consulta, no se mencionan.
		const { count: unchanged } = await admin
			.from('runs')
			.select('id', { count: 'exact', head: true })
			.eq('owner', owner)
			.eq('unchanged', true)
			.gte('started_at', since);
		const parts = [`${ok} al día`];
		if (held) parts.push(`${held} con la subida a la nube frenada por un cambio inusual`);
		if (late) parts.push(`${late} con retraso`);
		if (failed) parts.push(`${failed} con fallos`);
		if (onPause) parts.push(`${onPause} en pausa`);
		// Puntos en rojo de la salud de la protección: como mucho 3, el resto se cuenta.
		const red = weak.get(owner) ?? [];
		const redText = red.length ? ` Por revisar: ${red.slice(0, 3).join('; ')}${red.length > 3 ? ` y ${red.length - 3} más` : ''}.` : '';
		sent += await sendTo(admin, owner, {
			title: failed || late || held || red.length ? 'Resumen semanal: hay cosas por revisar' : 'Resumen semanal: todo en orden',
			body:
				`${count ?? 0} copias en los últimos 7 días` +
				(unchanged ? ` (y ${unchanged} ${unchanged === 1 ? 'revisión' : 'revisiones'} sin cambios)` : '') +
				` · repositorios: ${parts.join(', ')}.` +
				redText,
			url: '/',
			tag: 'resumen-semanal'
		});
		// Borra resúmenes de semanas anteriores y anota este.
		await admin.from('alert_state').delete().eq('owner', owner).like('alert_key', 'summary:%');
		await admin.from('alert_state').upsert({ owner, alert_key: week, level: 'ok', notified_at: now.toISOString() });
	}
	return sent;
}

/**
 * Destinos en pausa ahora (sin fecha de fin o con la fecha por llegar) por
 * usuario, de equipos no desvinculados. Los que fallaron ya cuentan como
 * fallos. Si la consulta falla (p. ej. aún sin la migración de pausas), 0.
 */
async function pausedByOwner(admin: SupabaseClient, now: Date) {
	const out = new Map<string, number>();
	const [{ data: repos, error: e1 }, { data: revoked, error: e2 }] = await Promise.all([
		admin.from('repos').select('owner, device_id, paused_until, last_run').eq('paused', true),
		admin.from('devices').select('id').not('revoked_at', 'is', null)
	]);
	if (e1 || e2) {
		console.error('notify: pausas', (e1 ?? e2)!.message);
		return out;
	}
	const gone = new Set((revoked ?? []).map((d) => d.id as string));
	for (const r of repos ?? []) {
		if (gone.has(r.device_id)) continue;
		if (r.paused_until && new Date(r.paused_until).getTime() <= now.getTime()) continue;
		if ((r.last_run as { result?: string } | null)?.result === 'error') continue;
		out.set(r.owner, (out.get(r.owner) ?? 0) + 1);
	}
	return out;
}

/**
 * Puntos en rojo («bad») de la salud de la protección por usuario, como
 * «Siigo: sin copia externa», de equipos no desvinculados. Si la consulta
 * falla (p. ej. aún sin la migración), ninguno.
 */
async function badProtectionByOwner(admin: SupabaseClient) {
	const out = new Map<string, string[]>();
	const [{ data: repos, error: e1 }, { data: revoked, error: e2 }] = await Promise.all([
		admin.from('repos').select('owner, device_id, name, protection').not('protection', 'is', null),
		admin.from('devices').select('id').not('revoked_at', 'is', null)
	]);
	if (e1 || e2) {
		console.error('notify: protección', (e1 ?? e2)!.message);
		return out;
	}
	const gone = new Set((revoked ?? []).map((d) => d.id as string));
	for (const r of repos ?? []) {
		if (gone.has(r.device_id)) continue;
		const items = ((r.protection as { items?: { state?: string; label?: string; detail?: string | null }[] } | null)?.items ?? []).filter(
			(i) => i.state === 'bad'
		);
		for (const i of items) {
			// Lo esencial del detalle («Sin kit: si pierdes…» → «sin kit»); si no hay, el nombre del punto.
			const text = ((i.detail ?? '').split(/[:.]/)[0] || i.label || '').trim().slice(0, 80);
			if (!text) continue;
			const list = out.get(r.owner) ?? [];
			list.push(`${r.name}: ${text.charAt(0).toLowerCase()}${text.slice(1)}`);
			out.set(r.owner, list);
		}
	}
	return out;
}
