// Notificaciones push: este navegador se suscribe con la clave pública VAPID y
// guarda la suscripción en Supabase. La función "notify" envía los avisos.
import { PUBLIC_VAPID_KEY } from '$env/static/public';
import { supabase } from '$lib/supabase';

export type PushState = 'unsupported' | 'ios-install' | 'denied' | 'off' | 'on';

const isIos = () => /iphone|ipad|ipod/i.test(navigator.userAgent);
const standalone = () =>
	matchMedia('(display-mode: standalone)').matches || (navigator as { standalone?: boolean }).standalone === true;

function keyBytes(b64: string) {
	const s = atob((b64 + '='.repeat((4 - (b64.length % 4)) % 4)).replace(/-/g, '+').replace(/_/g, '/'));
	return Uint8Array.from(s, (c) => c.charCodeAt(0));
}

async function registration() {
	return (await navigator.serviceWorker.getRegistration()) ?? navigator.serviceWorker.ready;
}

export async function pushState(): Promise<PushState> {
	if (!('serviceWorker' in navigator) || !('PushManager' in window) || !('Notification' in window)) {
		// En iPhone solo funcionan con la web añadida a la pantalla de inicio.
		return isIos() && !standalone() ? 'ios-install' : 'unsupported';
	}
	if (Notification.permission === 'denied') return 'denied';
	const sub = await (await registration()).pushManager.getSubscription();
	return sub ? 'on' : 'off';
}

export async function enablePush() {
	if ((await Notification.requestPermission()) !== 'granted') throw new Error('No se dio permiso para mostrar notificaciones.');
	const reg = await registration();
	const sub =
		(await reg.pushManager.getSubscription()) ??
		(await reg.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: keyBytes(PUBLIC_VAPID_KEY) }));
	const j = sub.toJSON();
	const { error } = await supabase.from('push_subscriptions').upsert(
		{ endpoint: sub.endpoint, p256dh: j.keys!.p256dh, auth: j.keys!.auth, user_agent: navigator.userAgent.slice(0, 300) },
		{ onConflict: 'endpoint' }
	);
	if (error) {
		await sub.unsubscribe();
		throw new Error(error.message);
	}
}

export async function disablePush() {
	const sub = await (await registration()).pushManager.getSubscription();
	if (!sub) return;
	await supabase.from('push_subscriptions').delete().eq('endpoint', sub.endpoint);
	await sub.unsubscribe();
}

export async function testPush() {
	const { data, error } = await supabase.functions.invoke('notify', { body: { test: true } });
	if (error) throw new Error(error.message);
	if (!data?.sent) throw new Error('No hay ningún dispositivo suscrito.');
}
