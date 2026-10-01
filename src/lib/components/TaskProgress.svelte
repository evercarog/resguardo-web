<script lang="ts">
	import { onMount } from 'svelte';
	import { LoaderCircle } from '@lucide/svelte';
	import { formatDate } from '$lib/format';
	import { freshLabel, taskProgress } from '$lib/status';
	import type { Device, Repo } from '$lib/types';

	// Verificación o subida a la copia externa en curso, con su progreso. Los
	// datos llegan solos (tiempo real) con cada informe del equipo; el reloj
	// propio solo refresca «actualizado hace N s».
	let { repo, device, now }: { repo: Repo; device: Device | null; now: number } = $props();

	let tick = $state(Date.now());
	onMount(() => {
		const t = setInterval(() => (tick = Date.now()), 5_000);
		return () => clearInterval(t);
	});
	const clock = $derived(Math.max(now, tick));
	const p = $derived(taskProgress(repo, clock));
</script>

{#if p}
	<div class="task" role="status">
		<p class="line">
			<span class="spin ic"><LoaderCircle size={14} aria-hidden="true" /></span>
			<span>
				<strong>{p.title}</strong>
				<span class="detail num" title={p.task.current_snapshot_time ? `Versión del ${formatDate(p.task.current_snapshot_time)}` : p.task.stage}>· {p.detail}</span>
			</span>
		</p>
		{#if p.percent != null}
			<div class="progress" aria-hidden="true"><span style:width="{p.percent}%"></span></div>
		{/if}
		{#if device?.last_seen_at}
			<span class="upd">Actualizado {freshLabel(device.last_seen_at, clock)}</span>
		{/if}
	</div>
{/if}

<style>
	.task {
		display: flex;
		flex-direction: column;
		gap: 6px;
		min-width: 0;
		font-size: var(--fs-sm);
		line-height: var(--lh-sm);
	}
	.line {
		display: flex;
		align-items: flex-start;
		gap: 8px;
	}
	.ic {
		flex: none;
		margin-top: 2px;
		color: var(--info);
	}
	strong {
		font-weight: 500;
	}
	.detail {
		color: var(--text-2);
	}
	.upd {
		font-size: var(--fs-xs);
		line-height: var(--lh-xs);
		color: var(--text-3);
	}
</style>
