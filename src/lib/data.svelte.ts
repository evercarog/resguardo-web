// Clientes, equipos y repositorios del usuario, con actualización en tiempo
// real: cuando un equipo informa, la web se actualiza sola.
import type { RealtimeChannel } from '@supabase/supabase-js';
import { supabase } from '$lib/supabase';
import type { Client, Device, Repo } from '$lib/types';

export const db = $state<{
	loaded: boolean;
	error: string;
	clients: Client[];
	devices: Device[];
	repos: Repo[];
}>({ loaded: false, error: '', clients: [], devices: [], repos: [] });

export async function loadAll() {
	const [c, d, r] = await Promise.all([
		supabase.from('clients').select('*').order('name'),
		supabase.from('devices').select('id, client_id, name, os, app_version, created_at, last_seen_at, revoked_at').order('name'),
		supabase.from('repos').select('*')
	]);
	const err = c.error ?? d.error ?? r.error;
	if (err) {
		db.error = err.message;
		return;
	}
	db.clients = c.data as Client[];
	db.devices = d.data as Device[];
	db.repos = r.data as Repo[];
	db.error = '';
	db.loaded = true;
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
		.subscribe();
}

export function unsubscribe() {
	if (channel) supabase.removeChannel(channel);
	channel = null;
}
