<script lang="ts">
	import { onMount } from 'svelte';
	import { Bell, BellOff, BellRing, CircleAlert, Send, Share } from '@lucide/svelte';
	import { disablePush, enablePush, pushState, testPush, type PushState } from '$lib/push';

	let ps = $state<PushState | null>(null);
	let busy = $state(false);
	let message = $state('');
	let error = $state('');

	onMount(async () => {
		ps = await pushState().catch(() => 'unsupported' as const);
	});

	async function act(fn: () => Promise<void>, ok = '') {
		busy = true;
		error = message = '';
		try {
			await fn();
			message = ok;
		} catch (e) {
			error = e instanceof Error ? e.message : String(e);
		} finally {
			ps = await pushState().catch(() => ps);
			busy = false;
		}
	}
</script>

{#if ps && ps !== 'unsupported'}
	<section class="card push">
		<span class="ic" class:on={ps === 'on'}>
			{#if ps === 'on'}<BellRing size={18} />{:else if ps === 'denied'}<BellOff size={18} />{:else}<Bell size={18} />{/if}
		</span>
		<div class="text">
			{#if ps === 'on'}
				<strong>Avisos activados en este dispositivo</strong>
				<span class="faint">Te avisamos si una copia falla, se atrasa o un equipo deja de conectarse, y cuando se recupera.</span>
			{:else if ps === 'off'}
				<strong>Recibe avisos en este dispositivo</strong>
				<span class="faint">Cuando una copia falle, se atrase o un equipo deje de conectarse.</span>
			{:else if ps === 'denied'}
				<strong>Las notificaciones están bloqueadas</strong>
				<span class="faint">Permítelas para esta web en los ajustes del navegador y vuelve a abrirla.</span>
			{:else}
				<strong>Avisos en el iPhone</strong>
				<span class="faint">Toca <Share size={12} /> Compartir → «Añadir a pantalla de inicio», abre Resguardo desde allí y actívalos.</span>
			{/if}
			{#if message}<span class="ok">{message}</span>{/if}
			{#if error}<span class="err"><CircleAlert size={13} /> {error}</span>{/if}
		</div>
		<div class="actions">
			{#if ps === 'off'}
				<button class="btn btn-primary btn-sm" disabled={busy} onclick={() => act(enablePush, 'Listo. Puedes enviar una prueba.')}>Activar</button>
			{:else if ps === 'on'}
				<button class="btn btn-sm" disabled={busy} onclick={() => act(testPush, 'Prueba enviada.')}><Send size={14} /> Probar</button>
				<button class="btn btn-ghost btn-sm" disabled={busy} onclick={() => act(disablePush)}>Desactivar</button>
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
