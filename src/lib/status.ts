// Estado de un repositorio y de un equipo (misma lógica que la app de escritorio).
import { bogota, bogotaTime, dayKey, formatBytes, formatDate, formatNumber, formatRelative, formatTime } from '$lib/format';
import type { Device, OffsiteHold, OffsiteSchedule, PlanSchedule, Repo, Schedule, VerifyConfig } from '$lib/types';

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

/** Nivel que se muestra en el chip: el del destino, o «cambio inusual» si la subida está frenada. */
export type ChipLevel = Level | 'held';
export const chipLevel = (repo: Repo, level: Level): ChipLevel => (repo.offsite_hold ? 'held' : level);

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
	return `los ${WEEKDAYS_PLURAL[s.weekday]}, ${s.time}`;
}

/**
 * Qué lee la verificación: «lee el 5 % de los datos», «solo la estructura» o,
 * rotativa, «Rotativa: todo el repositorio cada 12 verificaciones · próxima
 * parte 3 de 12 · último ciclo completo hace 2 meses».
 */
export function verifyModeLabel(v: VerifyConfig, now = Date.now()) {
	const n = v.rotate_parts ?? 0;
	if (n >= 2) {
		const parts = [`Rotativa: todo el repositorio cada ${n} verificaciones`];
		if (v.next_part != null && v.next_part >= 1 && v.next_part <= n) parts.push(`próxima parte ${v.next_part} de ${n}`);
		parts.push(v.last_full_at ? `último ciclo completo ${formatRelative(v.last_full_at, now)}` : 'todavía sin ciclo completo');
		return parts.join(' · ');
	}
	return v.subset_percent ? `lee el ${v.subset_percent} % de los datos` : 'solo la estructura';
}

/**
 * Verificación de la copia en la nube, en una línea: «Verificación de la nube:
 * hace 2 días, sin errores · los domingos, 05:00 · solo la estructura». Null
 * si no está programada.
 */
export function offsiteVerifySummary(repo: Repo, now = Date.now()) {
	const v = repo.maintenance?.offsite?.verify;
	if (!v) return null;
	const run = repo.offsite_verify_run ?? null;
	const res = run
		? `${formatRelative(run.finished ?? run.started, now)}, ${run.result === 'ok' ? 'sin errores' : run.result === 'warning' ? 'con avisos' : 'falló'}`
		: 'todavía ninguna';
	const rotating = (v.rotate_parts ?? 0) >= 2;
	const parts = [`Verificación de la nube: ${res}`, v.schedule ? scheduleLabel(v.schedule) : 'programada'];
	if (!rotating) parts.push(verifyModeLabel(v, now));
	return {
		text: parts.join(' · '),
		/** Línea aparte para la rotativa (es larga). */
		rotation: rotating ? verifyModeLabel(v, now) : null,
		result: run?.result ?? null,
		message: run?.result === 'error' ? run.message : null
	};
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
	const today = dayKey(now) === dayKey(h.since);
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

/** Servicios de la copia externa. */
export const OFFSITE_PROVIDERS: Record<string, string> = {
	b2: 'Backblaze B2',
	wasabi: 'Wasabi',
	r2: 'Cloudflare R2',
	aws: 'Amazon S3',
	s3: 'S3',
	otro: 'Otra ubicación'
};

/** Una tarea «en curso» de hace más de 72 h se da por cortada (una primera
 *  subida a la nube puede durar muchas horas; si el proceso muere, el equipo
 *  deja de informarla). */
export function taskRunning(repo: Repo, now = Date.now()) {
	const t = repo.task_running;
	return t && now - new Date(t.started).getTime() < 72 * HOUR ? t : null;
}

const num = (n: number | null | undefined): n is number => typeof n === 'number' && Number.isFinite(n);

/**
 * Verificación o subida en curso, en palabras:
 * «Subiendo a «Siigo · Backblaze B2»» + «versión 96 de 704 · 14 % · quedan ~25 min».
 * Sin total, la etapa y el tiempo que lleva.
 */
export function taskProgress(repo: Repo, now = Date.now()) {
	const t = taskRunning(repo, now);
	if (!t) return null;
	const off = repo.maintenance?.offsite;
	const target = off?.target_name ?? (off ? `${repo.name} · ${OFFSITE_PROVIDERS[off.provider] ?? 'copia externa'}` : 'la copia externa');
	const title =
		t.kind === 'verify' ? `Verificando «${repo.name}»` : t.kind === 'verify_offsite' ? `Verificando la copia en «${target}»` : `Subiendo a «${target}»`;
	const hasTotal = num(t.total) && t.total > 0;
	const hasBytes = num(t.bytes_total) && t.bytes_total > 0 && num(t.bytes_done);
	// El equipo envía el porcentaje como fracción (0 a 1).
	let percent = num(t.percent) ? t.percent * 100 : null;
	if (percent === null && hasBytes) percent = (t.bytes_done! / t.bytes_total!) * 100;
	if (percent === null && hasTotal) percent = (t.done / t.total!) * 100;
	if (percent !== null) percent = Math.min(100, Math.max(0, percent));
	const parts: string[] = [];
	// En la subida, `done` son las versiones ya subidas: se muestra la que va.
	if (hasTotal) parts.push(t.kind === 'offsite' ? `versión ${formatNumber(Math.min(t.done + 1, t.total!))} de ${formatNumber(t.total!)}` : `${formatNumber(t.done)} de ${formatNumber(t.total!)}`);
	if (hasBytes) parts.push(`${formatBytes(t.bytes_done)} de ${formatBytes(t.bytes_total)}`);
	if (percent !== null) parts.push(`${Math.floor(percent)} %`);
	if (num(t.eta_s) && t.eta_s > 0) parts.push(`quedan ~${elapsedLabel(t.eta_s / 3600)}`);
	// Sin progreso medible: la etapa y cuánto lleva.
	if (!parts.length) parts.push(t.stage || (t.kind === 'offsite' ? 'Subiendo…' : 'Verificando…'), `desde hace ${elapsedLabel((now - new Date(t.started).getTime()) / HOUR)}`);
	return { task: t, title, detail: parts.join(' · '), percent };
}

/** «hace 12 s», «hace 3 min»: frescura del último informe del equipo. */
export function freshLabel(iso: string, now = Date.now()) {
	const s = Math.max(0, Math.round((now - new Date(iso).getTime()) / 1000));
	return s < 60 ? `hace ${s} s` : s < 3600 ? `hace ${Math.round(s / 60)} min` : `hace ${elapsedLabel(s / 3600)}`;
}

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

const toMin = (hhmm: string) => {
	const m = /^(\d{1,2}):(\d{2})$/.exec(hhmm);
	return m ? Number(m[1]) * 60 + Number(m[2]) : null;
};

/** Minutos del día en que un plan lanza copias. */
function planMinutes(s: PlanSchedule): number[] {
	if (s.mode === 'at') return s.times.map(toMin).filter((m): m is number => m !== null);
	const from = toMin(s.from);
	const to = toMin(s.to);
	const every = Math.max(1, s.every_hours || 1) * 60;
	if (from === null || to === null) return [];
	const out: number[] = [];
	for (let m = from; m <= to && out.length < 48; m += every) out.push(m);
	return out;
}

/**
 * Próxima copia automática prevista según los planes (o el horario único de
 * antes). Los horarios son la hora del equipo, que está en Colombia (Bogotá).
 * Aproximada: null si no se puede saber.
 */
export function nextExpected(repo: Repo, now = Date.now()): Date | null {
	const base = bogota(now);
	const at = (dayOffset: number, minute: number) => bogotaTime(base.year, base.month, base.day + dayOffset, Math.floor(minute / 60), minute % 60);
	/** Día de la semana (0 = lunes) de hoy + `off` días, en Bogotá. */
	const weekday = (off: number) => (base.weekday + off) % 7;
	let best: Date | null = null;
	const consider = (d: Date) => {
		if (d.getTime() > now && (!best || d < best)) best = d;
	};
	const plans = (repo.plans ?? []).filter((p) => p.schedule);
	for (const p of plans) {
		const mins = planMinutes(p.schedule!);
		for (let off = 0; off <= 7; off++) {
			if (!p.schedule!.days.includes(weekday(off))) continue;
			for (const m of mins) consider(at(off, m));
		}
	}
	if (!plans.length && repo.schedule) {
		const s = repo.schedule;
		if (s.kind === 'daily' || s.kind === 'weekly') {
			const m = toMin(s.time);
			if (m !== null)
				for (let off = 0; off <= 7; off++) {
					if (s.kind === 'daily' || s.weekday === weekday(off)) consider(at(off, m));
				}
		} else if (s.kind === 'hours' && repo.last_snapshot_at) {
			consider(new Date(new Date(repo.last_snapshot_at).getTime() + s.every * HOUR));
		}
	}
	return best;
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
