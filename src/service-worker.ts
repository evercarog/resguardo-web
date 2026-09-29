/// <reference types="@sveltejs/kit" />
/// <reference no-default-lib="true"/>
/// <reference lib="esnext" />
/// <reference lib="webworker" />

// Service worker: guarda la "cáscara" de la app para que abra al instante
// (y sin conexión). Los datos siempre vienen de Supabase, nunca de caché.
import { build, files, version } from '$service-worker';

const sw = self as unknown as ServiceWorkerGlobalScope;
const CACHE = `resguardo-${version}`;
const ASSETS = [...build, ...files];

sw.addEventListener('install', (event) => {
	event.waitUntil(caches.open(CACHE).then((c) => c.addAll(ASSETS)));
});

sw.addEventListener('activate', (event) => {
	event.waitUntil(
		caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
	);
});

sw.addEventListener('fetch', (event) => {
	const req = event.request;
	const url = new URL(req.url);
	// Solo peticiones GET a esta misma web; Supabase y lo demás van directo a la red.
	if (req.method !== 'GET' || url.origin !== sw.location.origin) return;

	event.respondWith(
		(async () => {
			const cache = await caches.open(CACHE);
			// Archivos de la app (con versión en el nombre): desde la caché.
			if (ASSETS.includes(url.pathname)) {
				const hit = await cache.match(url.pathname);
				if (hit) return hit;
			}
			// Navegación: red primero; sin conexión, la página guardada.
			try {
				return await fetch(req);
			} catch {
				return (await cache.match(url.pathname)) ?? (await cache.match('/')) ?? Response.error();
			}
		})()
	);
});

// Avisos enviados por la función "notify".
sw.addEventListener('push', (event) => {
	let data: { title?: string; body?: string; url?: string; tag?: string } = {};
	try {
		data = event.data?.json() ?? {};
	} catch {
		data = { body: event.data?.text() };
	}
	// `renotify` y `timestamp` existen en los navegadores aunque falten en los tipos de TypeScript.
	// `renotify` sin `tag` da error, por eso solo cuando hay etiqueta.
	const options: NotificationOptions & { renotify?: boolean; timestamp?: number } = {
		body: data.body ?? '',
		tag: data.tag,
		renotify: !!data.tag,
		timestamp: Date.now(),
		icon: '/icons/icon-256.png',
		badge: '/icons/icon-256.png',
		data: { url: data.url ?? '/' }
	};
	event.waitUntil(sw.registration.showNotification(data.title ?? 'Resguardo', options));
});

// Al tocar el aviso: abre (o enfoca) la web en la página del repositorio.
sw.addEventListener('notificationclick', (event) => {
	event.notification.close();
	// Solo direcciones de esta misma web (nunca un sitio externo).
	let url = new URL((event.notification.data?.url as string) ?? '/', sw.location.origin);
	if (url.origin !== sw.location.origin) url = new URL('/', sw.location.origin);
	event.waitUntil(
		(async () => {
			const wins = await sw.clients.matchAll({ type: 'window', includeUncontrolled: true });
			for (const w of wins) {
				if (new URL(w.url).origin === sw.location.origin) {
					await w.focus();
					return (w as WindowClient).navigate(url.href);
				}
			}
			return sw.clients.openWindow(url.href);
		})()
	);
});
