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
				<span class="faint">Te avisamos si una copia falla, se atrasa o un equipo deja de conectarse, y cuando se recupera.</span>
			{:else if shared.ps === 'off'}
				<strong>Recibe avisos en este {device}</strong>
				<span class="faint">Cuando una copia falle, se atrase o un equipo deje de conectarse.</span>
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
		gap: 14px;
		padding: 14px 16px;
	}
	.push.compact {
		gap: 12px;
		padding: 10px 14px;
	}
	.ic {
		display: grid;
		place-items: center;
		flex: none;
		width: 38px;
		height: 38px;
		border-radius: 10px;
		color: var(--text-3);
		background: var(--surface-2, rgba(127, 127, 127, 0.1));
	}
	.compact .ic {
		width: 32px;
		height: 32px;
		border-radius: 8px;
	}
	.ic.on {
		color: var(--accent-soft-text, var(--accent));
		background: var(--accent-soft, rgba(127, 127, 127, 0.1));
	}
	.text {
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
		flex: 1;
		font-size: 13.5px;
	}
	.text .faint {
		font-size: 12.5px;
	}
	.compact .text {
		font-size: 13px;
	}
	.compact .text .faint {
		font-size: 12px;
	}
	.ok {
		color: var(--success, green);
		font-size: 12.5px;
	}
	.err {
		display: flex;
		align-items: center;
		gap: 4px;
		color: var(--danger, crimson);
		font-size: 12.5px;
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
