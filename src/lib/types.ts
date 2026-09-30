// Tablas de supabase/migrations (lo que la web puede leer).

export interface Client {
	id: string;
	name: string;
	created_at: string;
}

export interface Device {
	id: string;
	client_id: string | null;
	name: string;
	os: string | null;
	app_version: string | null;
	created_at: string;
	last_seen_at: string | null;
	revoked_at: string | null;
}

export type Schedule =
	| { kind: 'hours'; every: number }
	| { kind: 'daily'; time: string }
	| { kind: 'weekly'; weekday: number; time: string }
	/** Solo vigilar: las copias las hace otro programa; se esperan cada `every` horas. */
	| { kind: 'monitor'; every: number };

export interface RunInfo {
	started: string;
	finished: string;
	result: 'ok' | 'warning' | 'error';
	message: string;
	data_added?: number | null;
	/** Salió bien sin cambios: no creó versión («Solo guardar si hay cambios»). */
	unchanged?: boolean;
}

export interface Repo {
	device_id: string;
	repo_id: string;
	name: string;
	kind: string;
	host: string | null;
	schedule: Schedule | null;
	expected_hours: number | null;
	snapshots_count: number | null;
	last_snapshot_at: string | null;
	last_duration_s: number | null;
	last_data_added: number | null;
	last_total_bytes: number | null;
	last_run: RunInfo | null;
	/** Copia automática en marcha desde esta hora (la borra el informe siguiente). */
	running_since: string | null;
	/** Mantenimiento programado en el equipo (verificación y copia externa). */
	maintenance: Maintenance | null;
	verify_run: TaskRun | null;
	offsite_run: TaskRun | null;
	/** Verificación o subida en curso. */
	task_running: TaskRunning | null;
	/** Planes de copia (versiones con planes; en ese caso `schedule` va vacío). */
	plans: PlanInfo[] | null;
	/** Copias automáticas en pausa (opcional: no existe antes de la migración de pausas). */
	paused?: boolean;
	paused_since?: string | null;
	/** Fin de la pausa; null = hasta que se reanude a mano. */
	paused_until?: string | null;
	/** Cuándo terminó la última pausa (el retraso se cuenta desde aquí). */
	resumed_at?: string | null;
	/** Subida a la nube frenada por un cambio inusual (no existe antes de la migración 20260930020000). */
	offsite_hold?: OffsiteHold | null;
	updated_at: string;
}

/** Horario de un plan de copia. */
export interface PlanSchedule {
	/** 0 = lunes … 6 = domingo. */
	days: number[];
	/** 'at': a horas fijas; 'every': cada `every_hours` horas entre `from` y `to`. */
	mode: 'at' | 'every';
	/** Horas fijas 'HH:MM' (modo 'at'). */
	times: string[];
	every_hours: number;
	from: string;
	to: string;
}

/** Plan de copia tal como lo informa el equipo. */
export interface PlanInfo {
	id: string;
	name: string;
	tags: string[];
	/** Sin horario: el plan solo se lanza a mano. */
	schedule: PlanSchedule | null;
	last_run: TaskRun | null;
	/** «Solo guardar si hay cambios»: sin cambios, la copia no crea versión. */
	skip_unchanged?: boolean;
}

export interface Maintenance {
	verify: { schedule: Schedule | null; subset_percent: number } | null;
	offsite: { schedule: OffsiteSchedule | null; provider: string; target_name?: string | null; retention: boolean } | null;
}

/** Horario de la copia externa: los de siempre o después de cada copia con cambios (esperando `min_minutes`). */
export type OffsiteSchedule = Schedule | { kind: 'after_backup'; min_minutes: number };

/**
 * Subida a la nube frenada: una copia cambió mucho más de lo normal (posible
 * ransomware) y el equipo espera a que se revise antes de subirla.
 */
export interface OffsiteHold {
	since: string;
	snapshot_id: string | null;
	plan_name: string | null;
	data_added: number | null;
	files: number | null;
	typical_bytes: number | null;
	typical_files: number | null;
}

export interface TaskRun {
	started: string;
	finished: string | null;
	result: 'ok' | 'warning' | 'error';
	message: string | null;
	files_new?: number | null;
	/** Salió bien sin cambios: no creó versión. */
	unchanged?: boolean;
}

export interface TaskRunning {
	kind: 'verify' | 'offsite';
	started: string;
	stage: string;
	done: number;
	/** Progreso (versiones nuevas; las versiones antiguas no los envían). */
	total?: number | null;
	percent?: number | null;
	eta_s?: number | null;
	bytes_done?: number | null;
	bytes_total?: number | null;
	/** Fecha de la versión que se está subiendo o verificando. */
	current_snapshot_time?: string | null;
}

/** Snapshot informado por el equipo (solo metadatos). */
export interface SnapshotRow {
	device_id: string;
	repo_id: string;
	snapshot_id: string;
	time: string;
	hostname: string | null;
	tags: string[];
	duration_s: number | null;
	data_added: number | null;
	total_bytes: number | null;
	total_files: number | null;
	files_new: number | null;
	files_changed: number | null;
	files_unmodified: number | null;
}

export interface Run {
	id: number;
	device_id: string;
	repo_id: string;
	started_at: string;
	finished_at: string | null;
	result: 'ok' | 'warning' | 'error';
	message: string | null;
	data_added: number | null;
	/** Salió bien sin cambios (no existe antes de la migración 20260930010000). */
	unchanged?: boolean;
}
