// Estado de un repositorio y de un equipo (misma lógica que la app de escritorio).
import type { Device, Repo, Schedule } from '$lib/types';

const HOUR = 3_600_000;

/** Un equipo informa cada pocos minutos: más de 30 sin noticias = sin conexión. */
export const OFFLINE_AFTER_MIN = 30;

export type Level = 'ok' | 'late' | 'overdue' | 'failed' | 'empty';

export const LEVEL_LABEL: Record<Level, string> = {
	ok: 'Al día',
	late: 'Con retraso',
	overdue: 'Atrasada',
	failed: 'Falló',
	empty: 'Sin copias'
};

export const LEVEL_ORDER: Record<Level, number> = { failed: 0, overdue: 1, late: 2, empty: 3, ok: 4 };

/** Horas entre copias esperadas, según su programación. */
export function expectedHours(repo: Repo): number {
	if (repo.expected_hours) return repo.expected_hours;
	const s = repo.schedule;
	if (!s) return 24;
	return s.kind === 'hours' || s.kind === 'monitor' ? s.every : s.kind === 'daily' ? 24 : 168;
}

export function repoStatus(repo: Repo, now = Date.now()) {
	const expected = expectedHours(repo);
	const last = repo.last_snapshot_at ?? repo.last_run?.finished ?? null;
	const since = last ? (now - new Date(last).getTime()) / HOUR : null;
	let level: Level;
	if (repo.last_run?.result === 'error') level = 'failed';
	else if (since === null) level = 'empty';
	else if (since > expected * 2 + 1) level = 'overdue';
	else if (since > expected * 1.25 + 1) level = 'late';
	else level = 'ok';
	return { level, label: LEVEL_LABEL[level], expected, since, last };
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
