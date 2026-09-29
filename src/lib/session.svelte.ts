// Sesión y verificación en dos pasos. La base de datos exige aal2 (2FA
// completada) para ver o tocar cualquier dato, así que aquí solo se decide
// qué pantalla mostrar.
import type { Session } from '@supabase/supabase-js';
import { supabase } from '$lib/supabase';

export const auth = $state<{
	ready: boolean;
	session: Session | null;
	/** Nivel actual y el que se puede alcanzar (aal2 si hay un factor configurado). */
	level: 'aal1' | 'aal2' | null;
	next: 'aal1' | 'aal2' | null;
}>({ ready: false, session: null, level: null, next: null });

async function refreshLevel() {
	if (!auth.session) {
		auth.level = auth.next = null;
		return;
	}
	const { data } = await supabase.auth.mfa.getAuthenticatorAssuranceLevel();
	auth.level = (data?.currentLevel as 'aal1' | 'aal2') ?? null;
	auth.next = (data?.nextLevel as 'aal1' | 'aal2') ?? null;
}

let started = false;
export async function initAuth() {
	if (started) return;
	started = true;
	const { data } = await supabase.auth.getSession();
	auth.session = data.session;
	await refreshLevel();
	auth.ready = true;
	supabase.auth.onAuthStateChange((_event, session) => {
		auth.session = session;
		// Fuera del callback: la documentación de Supabase pide no esperar llamadas aquí dentro.
		setTimeout(refreshLevel, 0);
	});
}

export const refreshAuthLevel = refreshLevel;

export async function signOut() {
	// Los avisos de esta cuenta no deben seguir llegando a este dispositivo.
	try {
		const { disablePush } = await import('$lib/push');
		await disablePush();
	} catch {
		/* sin avisos o sin conexión: se cierra la sesión igualmente */
	}
	await supabase.auth.signOut();
	auth.session = null;
	auth.level = auth.next = null;
}
