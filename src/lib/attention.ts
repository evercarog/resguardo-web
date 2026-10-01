// Lo urgente, ordenado, para el resumen del inicio: qué falla, dónde y qué
// hacer. La alarma (tono «bad») solo para lo que de verdad es urgente; los
// retrasos leves y lo que falta para estar protegido del todo son avisos.
import { formatRelative } from '$lib/format';
import { HOLD_ADVICE, deviceOnline, elapsedLabel, holdSummary, repoStatus } from '$lib/status';
import type { Client, Device, Repo } from '$lib/types';

export interface UrgentItem {
	key: string;
	tone: 'bad' | 'warn';
	/** Orden: cuanto menor, más arriba. */
	rank: number;
	title: string;
	detail: string | null;
	/** Equipo · cliente. */
	where: string;
	href: string;
	action: string;
	/** Qué hacer, cuando no es evidente (cambio inusual). */
	advice?: string;
}

const repoHref = (r: Repo) => `/repo/${r.device_id}/${encodeURIComponent(r.repo_id)}`;

/** Lo esencial de un detalle de la salud de la protección («Sin kit: si…» → «sin kit»). */
function short(detail: string | null | undefined, label: string) {
	const t = ((detail ?? '').split(/[:.]/)[0] || label).trim();
	return t.charAt(0).toLowerCase() + t.slice(1);
}

export function urgentItems(repos: Repo[], devices: Device[], clients: Client[], now = Date.now()): UrgentItem[] {
	const out: UrgentItem[] = [];
	const live = devices.filter((d) => !d.revoked_at);
	const deviceOf = (r: Repo) => live.find((d) => d.id === r.device_id);
	const whereOf = (d: Device | undefined) => {
		const client = d?.client_id ? clients.find((c) => c.id === d.client_id) : null;
		return `${d?.name ?? 'Equipo'} · ${client?.name ?? 'Sin cliente'}`;
	};

	for (const d of live) {
		if (deviceOnline(d, now)) continue;
		const n = repos.filter((r) => r.device_id === d.id).length;
		out.push({
			key: `device:${d.id}`,
			tone: 'bad',
			rank: 5,
			title: `${d.name} no se conecta`,
			detail: d.last_seen_at
				? `Último contacto ${formatRelative(d.last_seen_at, now)}${n ? ` · ${n} ${n === 1 ? 'destino' : 'destinos'} sin noticias` : ''}. Comprueba que el equipo esté encendido y con Resguardo abierto.`
				: 'Todavía no ha enviado su estado.',
			where: whereOf(d).split(' · ')[1],
			href: `/#equipo-${d.id}`,
			action: 'Ver equipo'
		});
	}

	for (const r of repos) {
		const d = deviceOf(r);
		if (!d) continue;
		const where = whereOf(d);
		const href = repoHref(r);
		const name = `«${r.name}»`;
		const st = repoStatus(r, now);
		const online = deviceOnline(d, now);

		if (r.offsite_hold) {
			out.push({
				key: `hold:${r.device_id}:${r.repo_id}`,
				tone: 'bad',
				rank: 0,
				title: `Cambio inusual en ${name}`,
				detail: `${holdSummary(r.offsite_hold, now)} La subida a la nube está frenada.`,
				advice: HOLD_ADVICE,
				where,
				href,
				action: 'Revisar'
			});
		}
		if (st.level === 'failed') {
			out.push({
				key: `failed:${r.device_id}:${r.repo_id}`,
				tone: 'bad',
				rank: 1,
				title: `Falló la copia de ${name}`,
				detail: r.last_run?.message || null,
				where,
				href,
				action: 'Ver qué pasó'
			});
		} else if (online && st.level === 'overdue' && st.since !== null) {
			out.push({
				key: `overdue:${r.device_id}:${r.repo_id}`,
				tone: 'bad',
				rank: 6,
				title: `${name} atrasada`,
				detail: `Sin copias desde hace ${elapsedLabel(st.since)}: se esperaba una cada ${elapsedLabel(st.expected)}.`,
				where,
				href,
				action: 'Ver destino'
			});
		} else if (online && st.level === 'late' && st.since !== null) {
			out.push({
				key: `late:${r.device_id}:${r.repo_id}`,
				tone: 'warn',
				rank: 7,
				title: `${name} con retraso`,
				detail: `${elapsedLabel(st.since - st.expected)} de retraso.`,
				where,
				href,
				action: 'Ver destino'
			});
		}
		if (r.maintenance?.restore_test && r.restore_test_run?.result === 'error') {
			out.push({
				key: `restore:${r.device_id}:${r.repo_id}`,
				tone: 'bad',
				rank: 2,
				title: `Falló la prueba de restauración de ${name}`,
				detail: r.restore_test_run.message || null,
				where,
				href,
				action: 'Ver qué pasó'
			});
		}
		if (r.maintenance?.verify && r.verify_run?.result === 'error') {
			out.push({
				key: `verify:${r.device_id}:${r.repo_id}`,
				tone: 'bad',
				rank: 3,
				title: `La verificación de ${name} encontró errores`,
				detail: r.verify_run.message || null,
				where,
				href,
				action: 'Ver qué pasó'
			});
		}
		if (r.maintenance?.offsite && !r.offsite_hold && r.offsite_run?.result === 'error') {
			out.push({
				key: `offsite:${r.device_id}:${r.repo_id}`,
				tone: 'bad',
				rank: 4,
				title: `Falló la subida a la nube de ${name}`,
				detail: r.offsite_run.message || null,
				where,
				href,
				action: 'Ver qué pasó'
			});
		}
		if (r.maintenance?.offsite?.verify && r.offsite_verify_run?.result === 'error') {
			out.push({
				key: `vcloud:${r.device_id}:${r.repo_id}`,
				tone: 'bad',
				rank: 4,
				title: `Falló la verificación de la nube de ${name}`,
				detail: r.offsite_verify_run.message || null,
				where,
				href,
				action: 'Ver qué pasó'
			});
		}
		// Lo que falta para estar protegido del todo (sin repetir lo de arriba).
		for (const i of r.protection?.items ?? []) {
			if (i.state !== 'bad' || !['kit', 'externa', 'borrado'].includes(i.id)) continue;
			if (i.id === 'externa' && (r.offsite_hold || r.offsite_run?.result === 'error')) continue;
			out.push({
				key: `prot:${i.id}:${r.device_id}:${r.repo_id}`,
				tone: 'warn',
				rank: 8,
				title: `${name}: ${short(i.detail, i.label)}`,
				detail: i.detail && i.detail.includes(':') ? i.detail.slice(i.detail.indexOf(':') + 1).trim() : null,
				where,
				href: `${href}#proteccion`,
				action: 'Ver cómo'
			});
		}
	}

	return out.sort((a, b) => a.rank - b.rank || a.title.localeCompare(b.title));
}
