<script lang="ts">
	import '../app.css';
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import { onMount } from 'svelte';
	import { Activity, BookOpen, Building2, FileText, History, LogOut, Palette, Plus, UserRoundCog, WifiOff } from '@lucide/svelte';
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
			<a class="brand" href="/"><Logo size={24} /><span>Resguardo</span></a>
			<nav class="nav-top" aria-label="Principal">
				{#each NAV as n}
					<a href={n.href} class:on={active(n.href)} aria-current={active(n.href) ? 'page' : undefined}><n.icon size={16} aria-hidden="true" />{n.label}</a>
				{/each}
			</nav>
			<div class="actions">
				<a
					class="icon-btn"
					class:on={path.startsWith('/ayuda')}
					href="/ayuda"
					title="Qué significa cada cosa"
					aria-label="Qué significa cada cosa"
					aria-current={path.startsWith('/ayuda') ? 'page' : undefined}><BookOpen size={16} /></a
				>
				<button class="icon-btn" title="Apariencia" aria-label="Apariencia" onclick={() => (showAppearance = true)}><Palette size={16} /></button>
				<a
					class="icon-btn"
					class:on={path.startsWith('/cuenta')}
					href="/cuenta"
					title="Seguridad de la cuenta"
					aria-label="Seguridad de la cuenta"
					aria-current={path.startsWith('/cuenta') ? 'page' : undefined}><UserRoundCog size={16} /></a
				>
				<button class="icon-btn" title="Cerrar sesión" aria-label="Cerrar sesión" onclick={() => (confirmLogout = true)}><LogOut size={16} /></button>
			</div>
		</header>
		{#if offline}
			<div class="offline" role="status"><WifiOff size={14} aria-hidden="true" /> Sin conexión. Mostraremos el estado en cuanto vuelva la red.</div>
		{/if}
		<main id="contenido" tabindex="-1">{@render children()}</main>
		<!-- En el celular, navegación abajo, al alcance del pulgar -->
		<nav class="nav-bottom" aria-label="Principal">
			{#each NAV as n}
				<a href={n.href} class:on={active(n.href)} aria-current={active(n.href) ? 'page' : undefined}>
					<span class="pill"><n.icon size={20} aria-hidden="true" /></span><span>{n.label}</span>
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
		display: flex;
		flex-direction: column;
		min-height: 100dvh;
	}
	/* Enlace para teclado: aparece al tabular y lleva directo al contenido. */
	.skip {
		position: absolute;
		top: 8px;
		left: 8px;
		z-index: 20;
		padding: 8px 12px;
		font-weight: 500;
		color: var(--accent-contrast);
		background: var(--accent);
		border-radius: var(--radius);
		transform: translateY(-200%);
	}
	.skip:focus {
		transform: none;
	}
	/* Barra superior: fina y tranquila; el activo, con fondo suave (sin barras de color). */
	.top {
		position: sticky;
		top: 0;
		z-index: 5;
		display: flex;
		align-items: center;
		gap: var(--sp-6);
		/* Instalada en el iPhone, la barra de estado queda encima (black-translucent). */
		height: var(--header-h);
		padding: env(safe-area-inset-top) max(24px, env(safe-area-inset-right)) 0 max(24px, env(safe-area-inset-left));
		background: color-mix(in srgb, var(--bg) 88%, transparent);
		backdrop-filter: saturate(1.4) blur(12px);
		border-bottom: 1px solid var(--border);
	}
	.brand {
		display: flex;
		align-items: center;
		gap: 10px;
		font-size: var(--fs-h2);
		font-weight: 600;
		letter-spacing: -0.01em;
		color: var(--text-1);
		text-decoration: none;
	}
	.brand:hover {
		text-decoration: none;
	}
	.nav-top {
		display: flex;
		flex: 1;
		gap: 2px;
	}
	.nav-top a {
		display: flex;
		align-items: center;
		gap: 6px;
		height: 32px;
		padding: 0 10px;
		font-size: var(--fs-body);
		font-weight: 500;
		color: var(--text-2);
		text-decoration: none;
		border-radius: var(--radius-sm);
		-webkit-tap-highlight-color: transparent;
		transition:
			background var(--dur-fast) var(--ease),
			color var(--dur-fast) var(--ease);
	}
	.nav-top a:hover {
		color: var(--text-1);
		background: var(--surface-2);
		text-decoration: none;
	}
	.nav-top a.on {
		color: var(--text-1);
		background: var(--surface-2);
	}
	.actions {
		display: flex;
		gap: 2px;
	}
	.actions a.on {
		color: var(--text-1);
		background: var(--surface-2);
	}
	.offline {
		position: sticky;
		top: var(--header-h);
		z-index: 4;
		display: flex;
		align-items: center;
		justify-content: center;
		gap: 6px;
		padding: 6px max(16px, env(safe-area-inset-right)) 6px max(16px, env(safe-area-inset-left));
		font-size: var(--fs-sm);
		font-weight: 500;
		text-align: center;
		color: var(--warn);
		background: color-mix(in srgb, var(--bg) 70%, var(--warn-soft));
		border-bottom: 1px solid color-mix(in srgb, var(--warn) 30%, transparent);
	}
	.offline :global(svg) {
		flex: none;
	}
	main {
		flex: 1;
		width: 100%;
		max-width: calc(1120px + 2 * var(--sp-8));
		margin: 0 auto;
		padding: var(--sp-8) max(var(--sp-8), env(safe-area-inset-right)) var(--sp-12) max(var(--sp-8), env(safe-area-inset-left));
	}
	main:focus,
	main:focus-visible {
		outline: none;
	}
	.nav-bottom {
		display: none;
	}
	@media (max-width: 1100px) {
		main {
			padding: var(--sp-6) max(var(--sp-6), env(safe-area-inset-right)) var(--sp-10) max(var(--sp-6), env(safe-area-inset-left));
		}
	}
	/* Tabletas: los cinco apartados caben arriba si el nombre de la marca se oculta. */
	@media (max-width: 900px) {
		.brand span {
			display: none;
		}
		.top {
			gap: var(--sp-4);
		}
		.nav-top a {
			padding: 0 8px;
		}
	}
	@media (max-width: 720px) {
		.nav-top {
			display: none;
		}
		.brand span {
			display: inline;
		}
		.top {
			justify-content: space-between;
			padding-left: max(16px, env(safe-area-inset-left));
			padding-right: max(12px, env(safe-area-inset-right));
		}
		main {
			padding: var(--sp-5) max(var(--sp-4), env(safe-area-inset-right)) calc(88px + env(safe-area-inset-bottom))
				max(var(--sp-4), env(safe-area-inset-left));
		}
		/* En el celular, navegación abajo, al alcance del pulgar. */
		.nav-bottom {
			position: fixed;
			right: 0;
			bottom: 0;
			left: 0;
			z-index: 5;
			display: grid;
			grid-auto-columns: minmax(0, 1fr);
			grid-auto-flow: column;
			padding: 6px max(8px, env(safe-area-inset-right)) calc(6px + env(safe-area-inset-bottom)) max(8px, env(safe-area-inset-left));
			background: color-mix(in srgb, var(--bg) 92%, transparent);
			backdrop-filter: saturate(1.4) blur(12px);
			border-top: 1px solid var(--border);
		}
		.nav-bottom a {
			display: flex;
			flex-direction: column;
			align-items: center;
			gap: 2px;
			min-width: 0;
			min-height: 48px;
			padding: 4px 0;
			font-size: var(--fs-xs);
			line-height: var(--lh-xs);
			font-weight: 500;
			white-space: nowrap;
			color: var(--text-3);
			text-decoration: none;
			-webkit-tap-highlight-color: transparent;
		}
		/* Activo: texto principal y una píldora detrás del icono (no solo color). */
		.pill {
			display: grid;
			place-items: center;
			width: min(52px, 100%);
			height: 28px;
			border-radius: 999px;
			transition: background var(--dur-fast) var(--ease);
		}
		.nav-bottom a.on {
			color: var(--text-1);
		}
		.nav-bottom a.on .pill {
			background: var(--surface-2);
		}
	}
	@media print {
		.top,
		.nav-bottom,
		.offline {
			display: none !important;
		}
		main {
			max-width: none !important;
			padding: 0 !important;
		}
	}
</style>
