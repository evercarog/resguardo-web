<script lang="ts">
	import '../app.css';
	import { goto } from '$app/navigation';
	import { page } from '$app/state';
	import { Activity, Building2, LogOut, Palette, Plus } from '@lucide/svelte';
	import Logo from '$lib/components/Logo.svelte';
	import AppearanceDialog from '$lib/components/AppearanceDialog.svelte';
	import { auth, initAuth, signOut } from '$lib/session.svelte';
	import { initAppearance } from '$lib/settings.svelte';

	let { children } = $props();
	let showAppearance = $state(false);

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
		{ href: '/vincular', label: 'Vincular', icon: Plus },
		{ href: '/clientes', label: 'Clientes', icon: Building2 }
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
		<header class="top">
			<a class="brand" href="/"><Logo size={28} /><span>Resguardo</span></a>
			<nav class="nav-top">
				{#each NAV as n}
					<a href={n.href} class:on={active(n.href)}><n.icon size={16} />{n.label}</a>
				{/each}
			</nav>
			<div class="actions">
				<button class="icon-btn" title="Apariencia" onclick={() => (showAppearance = true)}><Palette size={17} /></button>
				<button class="icon-btn" title="Cerrar sesión" onclick={logout}><LogOut size={17} /></button>
			</div>
		</header>
		<main>{@render children()}</main>
		<!-- En el celular, navegación abajo, al alcance del pulgar -->
		<nav class="nav-bottom">
			{#each NAV as n}
				<a href={n.href} class:on={active(n.href)}><n.icon size={20} /><span>{n.label}</span></a>
			{/each}
		</nav>
	</div>
	{#if showAppearance}<AppearanceDialog onclose={() => (showAppearance = false)} />{/if}
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
		height: 60px;
		padding: 0 max(20px, env(safe-area-inset-left));
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
	main {
		flex: 1;
		width: 100%;
		max-width: 1100px;
		margin: 0 auto;
		padding: 24px 20px 40px;
	}
	.nav-bottom {
		display: none;
	}
	@media (max-width: 720px) {
		.nav-top {
			display: none;
		}
		.top {
			justify-content: space-between;
		}
		main {
			padding: 16px 14px calc(84px + env(safe-area-inset-bottom));
		}
		.nav-bottom {
			position: fixed;
			left: 0;
			right: 0;
			bottom: 0;
			z-index: 5;
			display: grid;
			grid-template-columns: repeat(3, 1fr);
			padding: 6px 8px calc(6px + env(safe-area-inset-bottom));
			background: color-mix(in srgb, var(--surface) 92%, transparent);
			backdrop-filter: blur(12px);
			border-top: 1px solid var(--border);
		}
		.nav-bottom a {
			display: flex;
			flex-direction: column;
			align-items: center;
			gap: 3px;
			padding: 6px 0;
			font-size: 11.5px;
			font-weight: 600;
			color: var(--text-3);
			text-decoration: none;
			border-radius: var(--radius);
		}
		.nav-bottom a.on {
			color: var(--accent-soft-text);
		}
	}
</style>
