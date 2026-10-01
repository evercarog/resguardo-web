<script lang="ts">
	import { CircleAlert, CircleCheck, LoaderCircle, Play, TriangleAlert } from '@lucide/svelte';
	import RelTime from '$lib/components/RelTime.svelte';
	import { db, friendlyError, loadCommands } from '$lib/data.svelte';
	import { deviceOnline, runningSince } from '$lib/status';
	import { supabase } from '$lib/supabase';
	import type { Device, Repo } from '$lib/types';

	// «Copiar ahora» de una copia (plan) desde la web: solo si el equipo lo
	// permite (lo activa él, en local) y está conectado. Debajo, cómo va la
	// última petición: pedida → en marcha → hecha o falló.
	let {
		repo,
		planId,
		planName,
		device,
		now,
		statusOnly = false
	}: { repo: Repo; planId: string; planName: string; device: Device | null; now: number; statusOnly?: boolean } = $props();

	let busy = $state(false);
	let error = $state('');

	const DAY = 86_400_000;
	const last = $derived(db.commands.find((c) => c.device_id === repo.device_id && c.repo_id === repo.repo_id && c.plan_id === planId) ?? null);
	const live = $derived(last?.status === 'pending' || last?.status === 'claimed');
	/** Los resultados se muestran durante un día. */
	const recent = $derived(!!last && now - new Date(last.finished_at ?? last.requested_at).getTime() < DAY);
	const allowed = $derived(!!device?.remote_backup_enabled);
	const online = $derived(!!device && deviceOnline(device, now));

	async function request() {
		busy = true;
		error = '';
		const { error: e } = await supabase.rpc('request_remote_backup', {
			p_device: repo.device_id,
			p_repo: repo.repo_id,
			p_plan: planId,
			p_from: 'web'
		});
		busy = false;
		if (e) {
			error = friendlyError(e.message);
			return;
		}
		await loadCommands();
	}
</script>

{#if allowed && online && !statusOnly}
	<button
		class="btn btn-sm"
		onclick={request}
		disabled={busy || live}
		title={live ? 'Ya hay una copia pedida: espera a que termine' : undefined}
		aria-label="Copiar ahora «{planName}»"
	>
		{#if busy}<span class="spin"><LoaderCircle size={14} /></span>{:else}<Play size={14} />{/if}
		Copiar ahora
	</button>
{/if}

{#if error}
	<span class="st tone-bad" role="alert"><CircleAlert size={13} aria-hidden="true" /> {error}</span>
{:else if last && (live || recent)}
	<span class="st" role="status">
		{#if last.status === 'pending'}
			<span class="tone-info ic"><LoaderCircle size={13} aria-hidden="true" /></span>
			<span>{statusOnly ? `«${planName}»: pedida` : 'Pedida'} <RelTime iso={last.requested_at} {now} /> · empieza en menos de 5 minutos</span>
		{:else if last.status === 'claimed'}
			<span class="tone-info ic spin"><LoaderCircle size={13} aria-hidden="true" /></span>
			<span>{statusOnly ? `«${planName}»: ` : ''}{runningSince(repo, now) ? 'En marcha' : 'El equipo la recibió · empezando'}</span>
		{:else if last.status === 'done'}
			<span class="tone-ok ic"><CircleCheck size={13} aria-hidden="true" /></span>
			<span>{statusOnly ? `«${planName}»: hecha` : 'Hecha'} <RelTime iso={last.finished_at ?? last.requested_at} {now} /></span>
		{:else if last.status === 'failed'}
			<span class="tone-bad ic"><CircleAlert size={13} aria-hidden="true" /></span>
			<span class="tone-bad txt">{statusOnly ? `«${planName}»: falló` : 'Falló'}{last.message ? `: ${last.message}` : ''}</span>
		{:else if last.status === 'rejected'}
			<span class="tone-warn ic"><TriangleAlert size={13} aria-hidden="true" /></span>
			<span>El equipo la rechazó{last.message ? `: ${last.message}` : ''}</span>
		{:else}
			<span class="tone-warn ic"><TriangleAlert size={13} aria-hidden="true" /></span>
			<span>Caducó: el equipo no la recogió a tiempo</span>
		{/if}
	</span>
{/if}

<style>
	.st {
		display: inline-flex;
		align-items: flex-start;
		gap: 6px;
		font-size: var(--fs-xs);
		line-height: var(--lh-xs);
		color: var(--text-2);
		overflow-wrap: anywhere;
	}
	.st.tone-bad {
		color: var(--bad);
	}
	.ic {
		display: inline-grid;
		flex: none;
		margin-top: 1px;
		color: var(--tone);
	}
	.txt {
		color: var(--tone);
	}
</style>
