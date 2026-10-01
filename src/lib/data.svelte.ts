// Clientes, equipos y repositorios del usuario, con actualización en tiempo
// real: cuando un equipo informa, la web se actualiza sola.
import type { RealtimeChannel } from '@supabase/supabase-js';
import { supabase } from '$lib/supabase';
import type { Client, Device, DeviceCommand, Repo } from '$lib/types';

export const db = $state<{
	loaded: boolean;
	error: string;
	/** Cuándo terminó la última carga correcta (ms), para "actualizado hace…". */
	updatedAt: number | null;
	clients: Client[];
	devices: Device[];
	repos: Repo[];
	/** Peticiones de copias a distancia recientes (las más nuevas primero). */
	commands: DeviceCommand[];
}>({ loaded: false, error: '', updatedAt: null, clients: [], devices: [], repos: [], commands: [] });

/** Peticiones recientes. Si la tabla aún no existe (antes de la migración), ninguna. */
export async function loadCommands() {
	const { data, error } = await supabase.from('device_commands').select('*').order('requested_at', { ascending: false }).limit(300);
	if (!error) db.commands = (data ?? []) as DeviceCommand[];
}

/** Fallos de red (sin conexión, DNS, servidor inalcanzable) según cada navegador. */
const NETWORK = /failed to fetch|fetch failed|networkerror|network request failed|load failed|network error|err_internet/i;

export const OFFLINE_MESSAGE = 'Sin conexión. Mostraremos el estado en cuanto vuelva la red.';

/** Mensaje para mostrar: los fallos de red se explican en lenguaje llano. */
export function friendlyError(message: string) {
	if ((typeof navigator !== 'undefined' && !navigator.onLine) || NETWORK.test(message)) return OFFLINE_MESSAGE;
	return message;
}

/**
 * Justo después de iniciar sesión, el servidor de datos puede tener el reloj
 * unas décimas por detrás del que emitió la sesión y responder "JWT issued at
 * future". Es pasajero: se reintenta unos segundos antes de mostrar un error.
 */
const CLOCK_SKEW = /issued at future|iat|not yet valid/i;
const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));

export async function loadAll(attempt = 0): Promise<void> {
	let results;
	try {
		results = await Promise.all([
			supabase.from('clients').select('*').order('name'),
			// Todas las columnas: así funciona antes y después de las migraciones que añaden alguna.
			supabase.from('devices').select('*').order('name'),
			supabase.from('repos').select('*')
		]);
	} catch (e) {
		db.error = friendlyError(e instanceof Error ? e.message : String(e));
		return;
	}
	const [c, d, r] = results;
	const err = c.error ?? d.error ?? r.error;
	if (err) {
		if (CLOCK_SKEW.test(err.message) && attempt < 5) {
			await wait(1000 * (attempt + 1));
			return loadAll(attempt + 1);
		}
		db.error = CLOCK_SKEW.test(err.message)
			? 'La hora de este dispositivo y la del servidor no coinciden. Comprueba que la fecha y hora del celular estén en automático y recarga.'
			: friendlyError(err.message);
		return;
	}
	db.clients = c.data as Client[];
	db.devices = d.data as Device[];
	db.repos = r.data as Repo[];
	db.error = '';
	db.loaded = true;
	db.updatedAt = Date.now();
	await loadCommands();
	// Tiempo real en cuanto hay una carga correcta (también si la primera falló sin conexión).
	subscribe();
}

let channel: RealtimeChannel | null = null;

export function subscribe() {
	if (channel) return;
	channel = supabase
		.channel('estado')
		.on('postgres_changes', { event: '*', schema: 'public', table: 'repos' }, (p) => {
			if (p.eventType === 'DELETE') {
				const old = p.old as Partial<Repo>;
				db.repos = db.repos.filter((r) => !(r.device_id === old.device_id && r.repo_id === old.repo_id));
			} else {
				const row = p.new as Repo;
				const i = db.repos.findIndex((r) => r.device_id === row.device_id && r.repo_id === row.repo_id);
				if (i >= 0) db.repos[i] = row;
				else db.repos.push(row);
			}
		})
		.on('postgres_changes', { event: '*', schema: 'public', table: 'devices' }, (p) => {
			if (p.eventType === 'DELETE') {
				db.devices = db.devices.filter((d) => d.id !== (p.old as Partial<Device>).id);
			} else {
				const row = p.new as Device;
				const i = db.devices.findIndex((d) => d.id === row.id);
				if (i >= 0) db.devices[i] = { ...db.devices[i], ...row };
				else db.devices.push(row);
			}
		})
		// Copias a distancia: el estado de cada petición cambia solo (pedida → en marcha → hecha).
		.on('postgres_changes', { event: '*', schema: 'public', table: 'device_commands' }, (p) => {
			if (p.eventType === 'DELETE') {
				db.commands = db.commands.filter((c) => c.id !== (p.old as Partial<DeviceCommand>).id);
			} else {
				const row = p.new as DeviceCommand;
				const i = db.commands.findIndex((c) => c.id === row.id);
				if (i >= 0) db.commands[i] = row;
				else db.commands.unshift(row);
			}
		})
		.subscribe();
}

export function unsubscribe() {
	if (channel) supabase.removeChannel(channel);
	channel = null;
}
