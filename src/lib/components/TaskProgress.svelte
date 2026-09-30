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
			<span class="spin"><LoaderCircle size={13} /></span>
			<span
				><strong>{p.title}</strong>: <span title={p.task.current_snapshot_time ? `Versión del ${formatDate(p.task.current_snapshot_time)}` : p.task.stage}
					>{p.detail}</span
				></span
			>
		</p>
		{#if p.percent != null}
			<div class="bar" aria-hidden="true"><span style:width="{p.percent}%"></span></div>
		{/if}
		{#if device?.last_seen_at}
			<span class="upd">actualizado {freshLabel(device.last_seen_at, clock)}</span>
		{/if}
	</div>
{/if}

<style>
	.task {
		display: flex;
		flex-direction: column;
		gap: 5px;
		font-size: 12px;
	}
	.line {
		display: flex;
		align-items: center;
		gap: 6px;
		margin: 0;
		color: var(--accent);
		font-weight: 600;
	}
	.line strong {
		font-weight: 650;
	}
	.bar {
		height: 5px;
		overflow: hidden;
		border-radius: 999px;
		background: color-mix(in srgb, var(--accent) 15%, var(--surface-3));
	}
	.bar span {
		display: block;
		height: 100%;
		border-radius: inherit;
		background: var(--accent);
		transition: width 0.4s ease;
	}
	.upd {
		font-size: 11px;
		color: var(--text-3);
	}
	.spin {
		display: grid;
		flex: none;
		animation: spin 1s linear infinite;
	}
	@keyframes spin {
		to {
			transform: rotate(360deg);
		}
	}
	@media (prefers-reduced-motion: reduce) {
		.spin {
			animation: none;
		}
		.bar span {
			transition: none;
		}
	}
</style>
