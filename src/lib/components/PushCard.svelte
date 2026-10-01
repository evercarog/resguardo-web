<script lang="ts" module>
	import type { PushState } from '$lib/push';

	const DISMISS_KEY = 'resguardo:avisos-ahora-no';

	function readDismissed() {
		try {
			return localStorage.getItem(DISMISS_KEY) === '1';
		} catch {
			return false;
		}
	}

	/**
	 * Estado compartido entre las dos ubicaciones de la tarjeta (arriba, para
	 * invitar a activar; abajo, compacta, para gestionarlos): solo se ve una.
	 */
	const shared = $state<{
		ps: PushState | null;
		dismissed: boolean;
		busy: boolean;
		message: string;
		error: string;
		confirmOff: boolean;
	}>({ ps: null, dismissed: false, busy: false, message: '', error: '', confirmOff: false });
	/** Cuenta para la que se consultó el estado (al cambiar de cuenta se vuelve a consultar). */
	let started: string | null = null;
</script>

<script lang="ts">
	import { onMount } from 'svelte';
	import { Bell, BellOff, BellRing, CircleAlert, Send, Share } from '@lucide/svelte';
	import { disablePush, enablePush, isIos, pushState, testPush, PushError } from '$lib/push';
	import { auth } from '$lib/session.svelte';

	/** Cómo llamar a este dispositivo en los textos. */
	function deviceWord() {
		const nav = navigator as Navigator & { userAgentData?: { mobile?: boolean } };
		if (nav.userAgentData?.mobile === true) return 'celular';
		const ua = navigator.userAgent;
		if (/iPad|Tablet/i.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1)) return 'dispositivo';
		if (/iPhone|iPod|Android.*Mobile|Mobile/i.test(ua)) return 'celular';
		return 'computador';
	}
	const device = deviceWord();

	/** 'top': invitación tras los contadores. 'bottom': versión compacta al final. */
	let { placement }: { placement: 'top' | 'bottom' } = $props();

	onMount(async () => {
		const user = auth.session?.user.id ?? '';
		if (started === user) return;
		started = user;
		shared.ps = null;
		shared.dismissed = readDismissed();
		shared.ps = await pushState().catch(() => 'unsupported' as const);
	});

	const invite = $derived((shared.ps === 'off' || shared.ps === 'ios-install') && !shared.dismissed);
	const visible = $derived(shared.ps !== null && shared.ps !== 'unsupported' && (placement === 'top' ? invite : !invite));

	async function act(fn: () => Promise<void>, ok: string, fallback: string) {
		shared.busy = true;
		shared.error = shared.message = '';
		shared.confirmOff = false;
		try {
			await fn();
			shared.message = ok;
		} catch (e) {
			// Los mensajes propios se muestran tal cual; el resto, en lenguaje llano.
			console.error(e);
			shared.error = e instanceof PushError ? e.message : fallback;
		} finally {
			shared.ps = await pushState().catch(() => shared.ps);
			shared.busy = false;
		}
	}

	function dismiss() {
		shared.dismissed = true;
		try {
			localStorage.setItem(DISMISS_KEY, '1');
		} catch {
			/* sin almacenamiento: vale solo para esta visita */
		}
	}
</script>

{#if visible}
	<section class="card push" class:compact={placement === 'bottom'}>
		<span class="ic" class:on={shared.ps === 'on'}>
			{#if shared.ps === 'on'}<BellRing size={18} />{:else if shared.ps === 'denied'}<BellOff size={18} />{:else}<Bell size={18} />{/if}
		</span>
		<div class="text">
			{#if shared.ps === 'on'}
				<strong>Avisos activados en este dispositivo</strong>
				<span class="faint">Te avisamos si una copia falla o se atrasa, si un equipo deja de conectarse o si hay un cambio inusual, y cuando se recupera.</span>
			{:else if shared.ps === 'off'}
				<strong>Recibe avisos en este {device}</strong>
				<span class="faint">Cuando una copia falle o se atrase, un equipo deje de conectarse o haya un cambio inusual.</span>
			{:else if shared.ps === 'denied'}
				<strong>Las notificaciones están bloqueadas</strong>
				<span class="faint">
					{#if isIos()}En iPhone: Ajustes → Notificaciones → Resguardo.{:else}Permítelas para esta web en los ajustes del navegador y vuelve a abrirla.{/if}
				</span>
			{:else}
				<strong>Avisos en el iPhone</strong>
				<span class="faint">Toca <Share size={12} /> Compartir → «Añadir a pantalla de inicio», abre Resguardo desde allí y actívalos.</span>
			{/if}
			{#if shared.message}<span class="ok" role="status">{shared.message}</span>{/if}
			{#if shared.error}<span class="err" role="alert"><CircleAlert size={13} /> {shared.error}</span>{/if}
		</div>
		<div class="actions">
			{#if shared.ps === 'off'}
				{#if placement === 'top'}
					<button class="btn btn-ghost btn-sm" disabled={shared.busy} onclick={dismiss}>Ahora no</button>
				{/if}
				<button
					class="btn btn-primary btn-sm"
					disabled={shared.busy}
					onclick={() => act(enablePush, 'Listo. Puedes enviar una prueba.', 'No se pudo activar. Inténtalo de nuevo.')}>Activar</button
				>
			{:else if shared.ps === 'ios-install' && placement === 'top'}
				<button class="btn btn-ghost btn-sm" onclick={dismiss}>Ahora no</button>
			{:else if shared.ps === 'on'}
				{#if shared.confirmOff}
					<button class="btn btn-ghost btn-sm" disabled={shared.busy} onclick={() => (shared.confirmOff = false)}>Cancelar</button>
					<button
						class="btn btn-danger btn-sm"
						disabled={shared.busy}
						onclick={() => act(disablePush, 'Avisos desactivados.', 'No se pudo desactivar. Inténtalo de nuevo.')}>¿Seguro? Desactivar</button
					>
				{:else}
					<button
						class="btn btn-sm"
						disabled={shared.busy}
						onclick={() => act(testPush, 'Prueba enviada.', 'No se pudo enviar la prueba. Inténtalo de nuevo.')}
						><Send size={14} /> Enviar prueba</button
					>
					<button class="btn btn-ghost btn-sm" disabled={shared.busy} onclick={() => (shared.confirmOff = true)}>Desactivar</button>
				{/if}
			{/if}
		</div>
	</section>
{/if}

<style>
	.push {
		display: flex;
		align-items: center;
		gap: var(--sp-4);
		padding: var(--sp-4) var(--sp-5);
	}
	.push.compact {
		gap: var(--sp-3);
		padding: var(--sp-3) var(--sp-4);
		background: transparent;
		border-style: dashed;
	}
	.ic {
		display: grid;
		flex: none;
		place-items: center;
		width: 36px;
		height: 36px;
		color: var(--text-2);
		background: var(--surface-2);
		border-radius: var(--radius);
	}
	.compact .ic {
		width: 32px;
		height: 32px;
	}
	.ic.on {
		color: var(--accent-text);
		background: var(--accent-soft);
	}
	.text {
		display: flex;
		flex: 1;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
		font-size: var(--fs-sm);
		line-height: var(--lh-sm);
	}
	.text strong {
		font-size: var(--fs-body);
		font-weight: 500;
	}
	.text .faint {
		font-size: var(--fs-sm);
	}
	.compact .text {
		font-size: var(--fs-sm);
	}
	.compact .text .faint {
		font-size: var(--fs-xs);
	}
	.ok {
		color: var(--ok);
		font-size: var(--fs-sm);
	}
	.err {
		display: flex;
		align-items: center;
		gap: 4px;
		color: var(--bad);
		font-size: var(--fs-sm);
	}
	.actions {
		display: flex;
		gap: 6px;
		flex: none;
	}
	.actions:empty {
		display: none;
	}
	@media (max-width: 640px) {
		.push {
			flex-wrap: wrap;
		}
		.actions {
			width: 100%;
			justify-content: flex-end;
		}
	}
</style>
