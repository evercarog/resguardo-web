<script lang="ts">
	import '../app.css';
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import { onMount } from 'svelte';
	import { Activity, Building2, FileText, History, LogOut, Palette, Plus, UserRoundCog, WifiOff } from '@lucide/svelte';
	import Logo from '$lib/components/Logo.svelte';
	import AppearanceDialog from '$lib/components/AppearanceDialog.svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import { db, loadAll } from '$lib/data.svelte';
	import { auth, initAuth, signOut } from '$lib/session.svelte';
	import { initAppearance } from '$lib/settings.svelte';

	let { children } = $props();
	let showAppearance = $state(false);
	let confirmLogout = $state(false);
	let offline = $state(false);

	// Aviso de "sin conexión" y recarga de los datos en cuanto vuelve la red.
	onMount(() => {
		offline = !navigator.onLine;
		const goOffline = () => (offline = true);
		const goOnline = () => {
			offline = false;
			// Solo con sesión y si ya se intentó cargar (con éxito o con error).
			if (inside && (db.loaded || db.error)) loadAll();
		};
		window.addEventListener('offline', goOffline);
		window.addEventListener('online', goOnline);
		return () => {
			window.removeEventListener('offline', goOffline);
			window.removeEventListener('online', goOnline);
		};
	});

	initAppearance();
	initAuth();

	const PUBLIC_ROUTES = ['/login', '/mfa'];
	const path = $derived(page.url.pathname);
	/** Dentro de la app solo con sesión y verificación en dos pasos completada. */
	const inside = $derived(!!auth.session && auth.level === 'aal2');

	// Redirecciones según el estado de la sesión.
	$effect(() => {
		if (!auth.ready) return;
		if (!auth.session && path !== '/login') goto('/login', { replaceState: true });
		else if (auth.session && auth.level !== 'aal2' && path !== '/mfa') goto('/mfa', { replaceState: true });
		else if (inside && PUBLIC_ROUTES.includes(path)) goto('/', { replaceState: true });
	});

	const NAV = [
		{ href: '/', label: 'Estado', icon: Activity },
		{ href: '/actividad', label: 'Actividad', icon: History },
		{ href: '/vincular', label: 'Vincular', icon: Plus },
		{ href: '/clientes', label: 'Clientes', icon: Building2 },
		{ href: '/informes', label: 'Informes', icon: FileText }
	];
	const active = (href: string) => (href === '/' ? path === '/' : path.startsWith(href));

	async function logout() {
		await signOut();
		goto('/login');
	}
</script>

{#if !auth.ready}
	<div class="boot"><Logo size={48} /></div>
{:else if inside}
	<div class="shell">
		<a class="skip" href="#contenido">Saltar al contenido</a>
		<header class="top">
			<a class="brand" href="/"><Logo size={28} /><span>Resguardo</span></a>
			<nav class="nav-top" aria-label="Principal">
				{#each NAV as n}
					<a href={n.href} class:on={active(n.href)} aria-current={active(n.href) ? 'page' : undefined}><n.icon size={16} />{n.label}</a>
				{/each}
			</nav>
			<div class="actions">
				<button class="icon-btn" title="Apariencia" aria-label="Apariencia" onclick={() => (showAppearance = true)}><Palette size={17} /></button>
				<a
					class="icon-btn"
					class:on={path.startsWith('/cuenta')}
					href="/cuenta"
					title="Seguridad de la cuenta"
					aria-label="Seguridad de la cuenta"
					aria-current={path.startsWith('/cuenta') ? 'page' : undefined}><UserRoundCog size={17} /></a
				>
				<button class="icon-btn" title="Cerrar sesión" aria-label="Cerrar sesión" onclick={() => (confirmLogout = true)}><LogOut size={17} /></button>
			</div>
		</header>
		{#if offline}
			<div class="offline" role="status"><WifiOff size={13} /> Sin conexión. Mostraremos el estado en cuanto vuelva la red.</div>
		{/if}
		<main id="contenido" tabindex="-1">{@render children()}</main>
		<!-- En el celular, navegación abajo, al alcance del pulgar -->
		<nav class="nav-bottom" aria-label="Principal">
			{#each NAV as n}
				<a href={n.href} class:on={active(n.href)} aria-current={active(n.href) ? 'page' : undefined}>
					<span class="pill"><n.icon size={20} /></span><span>{n.label}</span>
				</a>
			{/each}
		</nav>
	</div>
	{#if showAppearance}<AppearanceDialog onclose={() => (showAppearance = false)} />{/if}
	{#if confirmLogout}
		<ConfirmDialog
			title="¿Cerrar sesión?"
			message="Se cerrará en todos tus dispositivos. Para volver a entrar necesitarás tu contraseña y el código de verificación."
			confirmLabel="Cerrar sesión"
			onconfirm={logout}
			onclose={() => (confirmLogout = false)}
		/>
	{/if}
{:else if PUBLIC_ROUTES.includes(path)}
	<!-- Sin sesión (o sin 2FA) solo se muestran las pantallas de acceso -->
	{@render children()}
{:else}
	<div class="boot"><Logo size={48} /></div>
{/if}

<style>
	.boot {
		display: grid;
		place-items: center;
		height: 100dvh;
		animation: breathe 1.4s ease-in-out infinite alternate;
	}
	@keyframes breathe {
		to {
			opacity: 0.5;
		}
	}
	.shell {
		min-height: 100dvh;
		display: flex;
		flex-direction: column;
	}
	.top {
		position: sticky;
		top: 0;
		z-index: 5;
		display: flex;
		align-items: center;
		gap: 24px;
		/* Instalada en el iPhone, la barra de estado queda encima (black-translucent). */
		height: var(--header-h);
		padding: env(safe-area-inset-top) max(20px, env(safe-area-inset-right)) 0 max(20px, env(safe-area-inset-left));
		background: color-mix(in srgb, var(--surface) 85%, transparent);
		backdrop-filter: blur(10px);
		border-bottom: 1px solid var(--border);
	}
	.brand {
		display: flex;
		align-items: center;
		gap: 10px;
		font-family: var(--font-display);
		font-weight: 700;
		font-size: 16px;
		color: var(--text);
		text-decoration: none;
	}
	.nav-top {
		display: flex;
		gap: 4px;
		flex: 1;
	}
	.nav-top a {
		display: flex;
		align-items: center;
		gap: 7px;
		padding: 7px 12px;
		font-weight: 600;
		font-size: 13.5px;
		color: var(--text-2);
		text-decoration: none;
		border-radius: var(--radius-sm);
		-webkit-tap-highlight-color: transparent;
		transition:
			background 0.15s,
			color 0.15s;
	}
	.nav-top a:hover {
		background: var(--surface-3);
		color: var(--text);
	}
	.nav-top a.on {
		color: var(--accent-soft-text);
		background: var(--accent-soft);
	}
	.actions {
		display: flex;
		gap: 2px;
	}
	.actions a.on {
		color: var(--accent-soft-text);
		background: var(--accent-soft);
	}
	.offline {
		position: sticky;
		top: var(--header-h);
		z-index: 4;
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 6px;
		padding: 5px max(14px, env(safe-area-inset-right)) 5px max(14px, env(safe-area-inset-left));
		font-size: 12.5px;
		font-weight: 600;
		text-align: center;
		color: var(--warn);
		background: var(--warn-soft);
		border-bottom: 1px solid var(--border);
	}
	.offline :global(svg) {
		flex: none;
	}
	/* Enlace para teclado: aparece al tabular y lleva directo al contenido. */
	.skip {
		position: absolute;
		top: 8px;
		left: 8px;
		z-index: 20;
		padding: 8px 12px;
		font-weight: 600;
		color: var(--accent-contrast);
		background: var(--accent);
		border-radius: var(--radius-sm);
		transform: translateY(-200%);
	}
	.skip:focus {
		transform: none;
	}
	main:focus,
	main:focus-visible {
		outline: none;
		box-shadow: none;
	}
	main {
		flex: 1;
		width: 100%;
		max-width: 1100px;
		margin: 0 auto;
		padding: 24px max(20px, env(safe-area-inset-right)) 40px max(20px, env(safe-area-inset-left));
	}
	.nav-bottom {
		display: none;
	}
	/* Tabletas: los cinco apartados caben arriba si el nombre de la marca se oculta. */
	@media (max-width: 900px) {
		.brand span {
			display: none;
		}
		.top {
			gap: 16px;
		}
		.nav-top a {
			gap: 5px;
			padding: 7px 9px;
		}
	}
	@media (max-width: 720px) {
		.nav-top {
			display: none;
		}
		.top {
			justify-content: space-between;
		}
		main {
			padding: 16px max(14px, env(safe-area-inset-right)) calc(84px + env(safe-area-inset-bottom))
				max(14px, env(safe-area-inset-left));
		}
		.nav-bottom {
			position: fixed;
			left: 0;
			right: 0;
			bottom: 0;
			z-index: 5;
			/* Una columna igual por cada apartado (hasta 5 caben en 320 px). */
			display: grid;
			grid-auto-flow: column;
			grid-auto-columns: minmax(0, 1fr);
			padding: 6px max(8px, env(safe-area-inset-right)) calc(6px + env(safe-area-inset-bottom)) max(8px, env(safe-area-inset-left));
			background: color-mix(in srgb, var(--surface) 92%, transparent);
			backdrop-filter: blur(12px);
			border-top: 1px solid var(--border);
		}
		.nav-bottom a {
			display: flex;
			flex-direction: column;
			align-items: center;
			gap: 3px;
			min-width: 0;
			min-height: 48px;
			padding: 4px 0;
			font-size: 11.5px;
			white-space: nowrap;
			font-weight: 600;
			color: var(--text-3);
			text-decoration: none;
			border-radius: var(--radius);
			-webkit-tap-highlight-color: transparent;
		}
		/* Activo: color y además una píldora detrás del icono (no solo color). */
		.pill {
			display: grid;
			place-items: center;
			width: min(52px, 100%);
			height: 28px;
			border-radius: 999px;
			transition: background 0.15s;
		}
		.nav-bottom a.on {
			color: var(--accent-soft-text);
		}
		.nav-bottom a.on .pill {
			background: var(--accent-soft);
		}
	}
	@media print {
		.top,
		.nav-bottom,
		.offline {
			display: none !important;
		}
		main {
			padding: 0 !important;
			max-width: none !important;
		}
	}
</style>
