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
	updated_at: string;
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
}
