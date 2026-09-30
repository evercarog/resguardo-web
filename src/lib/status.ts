// Estado de un repositorio y de un equipo (misma lógica que la app de escritorio).
import { formatBytes, formatDate, formatNumber, formatTime } from '$lib/format';
import type { Device, OffsiteHold, OffsiteSchedule, PlanSchedule, Repo, Schedule } from '$lib/types';

const HOUR = 3_600_000;

/** Un equipo informa cada pocos minutos: más de 30 sin noticias = sin conexión. */
export const OFFLINE_AFTER_MIN = 30;

export type Level = 'ok' | 'late' | 'overdue' | 'failed' | 'empty' | 'paused';

export const LEVEL_LABEL: Record<Level, string> = {
	ok: 'Al día',
	late: 'Con retraso',
	overdue: 'Atrasada',
	failed: 'Falló',
	empty: 'Sin copias',
	paused: 'En pausa'
};

export const LEVEL_ORDER: Record<Level, number> = { failed: 0, overdue: 1, late: 2, empty: 3, paused: 4, ok: 5 };

/** Horas entre copias esperadas, según su programación. */
export function expectedHours(repo: Repo): number {
	if (repo.expected_hours) return repo.expected_hours;
	const s = repo.schedule;
	if (!s) return 24;
	return s.kind === 'hours' || s.kind === 'monitor' ? s.every : s.kind === 'daily' ? 24 : 168;
}

/**
 * Pausa de las copias automáticas (misma lógica que los avisos en el servidor).
 * - `active`: en pausa ahora (sin fecha de fin, o la fecha aún no llega).
 * - `until`: fin previsto (null = hasta que se reanude a mano).
 * - `resumedAt`: cuándo terminó la última pausa; el retraso se cuenta desde
 *   ahí, así no aparece "atrasada" nada más reanudar.
 */
export function pauseState(repo: Repo, now = Date.now()) {
	const until = repo.paused ? (repo.paused_until ?? null) : null;
	const active = !!repo.paused && (!until || new Date(until).getTime() > now);
	const ended = repo.paused ? until : (repo.resumed_at ?? null);
	return { active, until, since: repo.paused ? (repo.paused_since ?? null) : null, resumedAt: active ? null : ended };
}

const time = (iso: string | null | undefined) => {
	const t = iso ? new Date(iso).getTime() : NaN;
	return Number.isFinite(t) ? t : null;
};

/**
 * Última copia correcta (ok o con avisos) del destino o de cualquiera de sus
 * planes, la más reciente. Las que fallan no cuentan.
 */
export function lastOkRun(repo: Repo): { finished: string; unchanged: boolean } | null {
	const runs = [repo.last_run, ...(repo.plans ?? []).map((p) => p.last_run)];
	let best: { finished: string; unchanged: boolean } | null = null;
	for (const r of runs) {
		if (!r || (r.result !== 'ok' && r.result !== 'warning') || time(r.finished) === null) continue;
		if (!best || time(r.finished)! > time(best.finished)!) best = { finished: r.finished!, unchanged: r.unchanged === true };
	}
	return best;
}

/**
 * Última revisión correcta: la última versión o la última copia correcta, lo
 * más reciente (misma lógica que los avisos en el servidor). Con «Solo guardar
 * si hay cambios», una noche sin cambios no crea versión pero sí cuenta.
 */
export function lastCheck(repo: Repo) {
	const ok = lastOkRun(repo);
	const snap = time(repo.last_snapshot_at);
	const at = Math.max(snap ?? -Infinity, time(ok?.finished) ?? -Infinity);
	return {
		at: Number.isFinite(at) ? at : null,
		/** Revisión sin cambios más reciente que la última versión (para «última revisión … · sin cambios»). */
		unchangedAt: ok?.unchanged && (snap === null || time(ok.finished)! > snap) ? ok.finished : null
	};
}

export function repoStatus(repo: Repo, now = Date.now()) {
	const expected = expectedHours(repo);
	const last = repo.last_snapshot_at ?? repo.last_run?.finished ?? null;
	const pause = pauseState(repo, now);
	const check = lastCheck(repo);
	// El retraso se cuenta desde la última revisión correcta (o, si no hay
	// ninguna, desde la última copia); tras una pausa, desde que se reanudó.
	const base = check.at ?? time(last);
	const from = base !== null ? Math.max(base, time(pause.resumedAt) ?? 0) : null;
	const since = from !== null ? (now - from) / HOUR : null;
	let level: Level;
	if (repo.last_run?.result === 'error') level = 'failed';
	else if (pause.active) level = 'paused';
	else if (since === null) level = 'empty';
	else if (since > expected * 2 + 1) level = 'overdue';
	else if (since > expected * 1.25 + 1) level = 'late';
	else level = 'ok';
	return { level, label: LEVEL_LABEL[level], expected, since, last, unchangedAt: check.unchangedAt, pause };
}

/** Copia automática en curso (se ignora si lleva más de 12 h: el equipo se apagó a mitad). */
export function runningSince(repo: Repo, now = Date.now()): Date | null {
	if (!repo.running_since) return null;
	const t = new Date(repo.running_since);
	return now - t.getTime() < 12 * HOUR ? t : null;
}

export function deviceOnline(d: Device, now = Date.now()) {
	return !!d.last_seen_at && now - new Date(d.last_seen_at).getTime() < OFFLINE_AFTER_MIN * 60_000;
}

const WEEKDAYS = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];

export function scheduleLabel(s: Schedule | null) {
	if (!s) return 'sin programar';
	if (s.kind === 'monitor') return `vigilado · se esperan cada ${s.every === 24 ? 'día' : `${s.every} h`}`;
	if (s.kind === 'hours') return s.every === 1 ? 'cada hora' : `cada ${s.every} h`;
	if (s.kind === 'daily') return `diaria, ${s.time}`;
	return `los ${WEEKDAYS[s.weekday]}, ${s.time}`;
}

/** Horario de la copia externa (también «después de cada copia con cambios»). */
export function offsiteScheduleLabel(s: OffsiteSchedule | null) {
	if (s?.kind === 'after_backup') {
		const wait = s.min_minutes > 0 ? ` (espera ${s.min_minutes >= 60 && s.min_minutes % 60 === 0 ? `${s.min_minutes / 60} h` : `${s.min_minutes} min`})` : '';
		return `Después de cada copia con cambios${wait}`;
	}
	return scheduleLabel(s);
}

/**
 * Subida frenada, en una frase: «La copia «Documentos» de las 17:00 añadió
 * 38 GB y 12.400 archivos (lo normal: ~20 MB y ~40).»
 */
export function holdSummary(h: OffsiteHold, now = Date.now()) {
	const d = new Date(h.since);
	const today = new Date(now).toDateString() === d.toDateString();
	const when = today ? `de las ${formatTime(h.since)}` : `del ${formatDate(h.since)}`;
	const added = [h.data_added != null ? formatBytes(h.data_added) : null, h.files != null ? `${formatNumber(h.files)} archivos` : null]
		.filter(Boolean)
		.join(' y ');
	const usual = [h.typical_bytes != null ? `~${formatBytes(h.typical_bytes)}` : null, h.typical_files != null ? `~${formatNumber(h.typical_files)}` : null]
		.filter(Boolean)
		.join(' y ');
	return `La copia${h.plan_name ? ` «${h.plan_name}»` : ''} ${when} añadió ${added || 'mucho más de lo normal'}${usual ? ` (lo normal: ${usual})` : ''}.`;
}

/** Qué hacer ante una subida frenada. */
export const HOLD_ADVICE =
	'Revisa el cambio en Resguardo, en ese equipo, antes de confirmar la subida. Si sospechas un ransomware, aísla ese servidor (desconéctalo de la red): las versiones anteriores en el servidor de solo añadir siguen intactas.';

/** Nombre del día en plural, para «los domingos», «sábados»… */
const WEEKDAYS_PLURAL = ['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábados', 'domingos'];

/** Une una lista en español: «a, b y c». */
function joinList(items: string[]) {
	return items.length < 2 ? (items[0] ?? '') : `${items.slice(0, -1).join(', ')} y ${items.at(-1)}`;
}

/** Días de un plan: «todos los días», «lunes a viernes», «domingos», «lunes, miércoles y viernes». */
function daysLabel(days: number[]) {
	const d = [...new Set(days)].filter((n) => n >= 0 && n <= 6).sort((a, b) => a - b);
	if (d.length === 0) return 'ningún día';
	if (d.length === 7) return 'todos los días';
	if (d.length === 1) return WEEKDAYS_PLURAL[d[0]];
	// Tramo seguido de 3 días o más: «lunes a sábado»
	if (d.length >= 3 && d.at(-1)! - d[0] === d.length - 1) return `${WEEKDAYS[d[0]]} a ${WEEKDAYS[d.at(-1)!]}`;
	return joinList(d.map((n) => WEEKDAYS[n]));
}

/** «a las 13:00 y 18:30» (o «a la 01:30» si es una sola hora de la 1). */
function atLabel(times: string[]) {
	const t = [...times].sort();
	return `${t.length === 1 && t[0].startsWith('01:') ? 'a la' : 'a las'} ${joinList(t)}`;
}

/** Horario de un plan en lenguaje natural: «lunes a sábado, cada hora de 07:00 a 19:00». */
export function planScheduleLabel(s: PlanSchedule) {
	const days = daysLabel(s.days);
	if (s.mode === 'every') {
		const every = s.every_hours === 1 ? 'cada hora' : `cada ${s.every_hours} horas`;
		return `${days}, ${every} de ${s.from} a ${s.to}`;
	}
	return s.times.length ? `${days} ${atLabel(s.times)}` : days;
}

/** Programación de un repositorio: sus planes si los tiene; si no, el horario único de antes. */
export function repoScheduleLabel(repo: Repo) {
	const plans = repo.plans ?? [];
	if (!plans.length) return scheduleLabel(repo.schedule);
	if (plans.length === 1) {
		const p = plans[0];
		return `1 copia: ${p.schedule ? planScheduleLabel(p.schedule) : 'solo a mano'}`;
	}
	// Varios planes: sus nombres si caben; si no, solo cuántos hay.
	const names = plans.map((p) => p.name).join(', ');
	return names.length <= 40 ? `${plans.length} copias: ${names}` : `${plans.length} copias`;
}

/** «hasta el 3 oct 2026, 18:00» o «hasta que se reanude». */
export function pauseUntilLabel(until: string | null) {
	return until ? `hasta el ${formatDate(until)}` : 'hasta que se reanude';
}

export function elapsedLabel(hours: number) {
	if (hours < 1) return `${Math.max(1, Math.round(hours * 60))} min`;
	if (hours < 48) return `${Math.round(hours)} h`;
	return `${Math.round(hours / 24)} días`;
}

const KINDS: Record<string, string> = {
	local: 'Disco local',
	rest: 'Servidor REST',
	sftp: 'SFTP',
	s3: 'Amazon S3',
	b2: 'Backblaze B2',
	azure: 'Azure Blob',
	gs: 'Google Cloud Storage',
	rclone: 'rclone',
	other: 'Otro'
};
export const kindLabel = (k: string) => KINDS[k] ?? k;
