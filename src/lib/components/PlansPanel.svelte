<script lang="ts">
	import { onMount } from 'svelte';
	import { CalendarClock, Hand } from '@lucide/svelte';
	import RemoteBackup from '$lib/components/RemoteBackup.svelte';
	import RunResult from '$lib/components/RunResult.svelte';
	import { deviceOnline, planScheduleLabel } from '$lib/status';
	import type { Device, Repo } from '$lib/types';

	// Planes de copia del repositorio, tal como los informa el equipo, con
	// «Copiar ahora» si el equipo permite copias a distancia.
	let { repo, device, now }: { repo: Repo; device: Device | null; now: number } = $props();
	const plans = $derived(repo.plans ?? []);

	/** Copia señalada desde Estado (#copia-<id>): se lleva a la vista y se resalta. */
	let marked = $state('');
	onMount(() => {
		// Desde «Copiar ahora…» en Estado: a la lista de copias.
		if (location.hash === '#copias') {
			requestAnimationFrame(() => document.getElementById('copias')?.scrollIntoView({ block: 'start' }));
			return;
		}
		const id = decodeURIComponent(location.hash.replace(/^#copia-/, ''));
		if (!location.hash.startsWith('#copia-') || !plans.some((p) => p.id === id)) return;
		marked = id;
		requestAnimationFrame(() => document.getElementById(`copia-${id}`)?.scrollIntoView({ block: 'center' }));
	});
</script>

{#if plans.length}
	<section class="card panel plans" id="copias" aria-labelledby="t-plans">
		<div class="panel-head">
			<h2 class="section-title" id="t-plans">Copias que se guardan aquí</h2>
			{#if device?.managed_by}
				<p class="hint">Este equipo lo gestiona otro: sus copias se piden desde la consola, no desde la web.</p>
			{:else if device && !device.remote_backup_enabled}
				<p class="hint">Para copiar desde aquí, activa «Copias a distancia» en Resguardo, en ese equipo.</p>
			{:else if device && !deviceOnline(device, now)}
				<p class="hint">El equipo está sin conexión: podrás pedir una copia cuando vuelva a conectarse.</p>
			{/if}
		</div>
		<div class="rows">
			{#each plans as p (p.id)}
				<div class="row" class:off={!p.schedule} class:marked={marked === p.id} id="copia-{p.id}">
					<span class="ic" aria-hidden="true">
						{#if p.schedule}<CalendarClock size={16} />{:else}<Hand size={16} />{/if}
					</span>
					<div class="what">
						<div class="name">
							<strong>{p.name}</strong>
							{#each p.tags ?? [] as t}<span class="tag">{t}</span>{/each}
						</div>
						<span class="faint when"
							>{p.schedule ? planScheduleLabel(p.schedule) : 'Solo a mano'}{#if p.skip_unchanged}{' '}· Solo guarda si hay cambios{/if}</span
						>
					</div>
					<div class="state">
						<RunResult run={p.last_run} {now} />
						{#if p.last_run && p.last_run.result !== 'ok' && p.last_run.message}<span class="msg">{p.last_run.message}</span>{/if}
						<span class="remote"><RemoteBackup {repo} planId={p.id} planName={p.name} {device} {now} /></span>
					</div>
				</div>
			{/each}
		</div>
	</section>
{/if}

<style>
	/* Panel de filas (diseño común): cabecera de sección y filas de 44 px con separador. */
	.panel {
		padding: 0;
		overflow: hidden;
	}
	.panel-head {
		padding: var(--sp-5) var(--sp-5) var(--sp-3);
	}
	.rows {
		display: flex;
		flex-direction: column;
	}
	.row {
		display: grid;
		grid-template-columns: 16px minmax(0, 1fr) minmax(0, auto);
		align-items: start;
		gap: var(--sp-3);
		min-height: 44px;
		padding: var(--sp-3) var(--sp-5);
		border-top: 1px solid var(--border);
	}
	.ic {
		display: grid;
		padding-top: 2px;
		color: var(--text-2);
	}
	.row.off .ic,
	.row.off strong {
		color: var(--text-3);
	}
	.what {
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
	}
	.what strong {
		font-weight: 500;
	}
	.what .faint {
		font-size: var(--fs-sm);
		line-height: var(--lh-sm);
		overflow-wrap: anywhere;
	}
	.state {
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		gap: 2px;
		min-width: 0;
		padding-top: 1px;
		font-size: var(--fs-sm);
		line-height: var(--lh-sm);
		text-align: right;
	}
	.msg {
		max-width: 320px;
		font-size: var(--fs-xs);
		line-height: var(--lh-xs);
		color: var(--text-2);
		overflow-wrap: anywhere;
	}
	@media (max-width: 640px) {
		.row {
			grid-template-columns: 16px minmax(0, 1fr);
		}
		.state {
			grid-column: 2;
			align-items: flex-start;
			text-align: left;
		}
	}

	.plans {
		scroll-margin-top: calc(var(--header-h, 56px) + 16px);
	}
	.hint {
		margin-top: 2px;
		font-size: var(--fs-sm);
		line-height: var(--lh-sm);
		color: var(--text-3);
	}
	.remote {
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		gap: 4px;
		margin-top: 4px;
	}
	.remote:empty {
		display: none;
	}
	@media (max-width: 640px) {
		.remote {
			align-items: flex-start;
		}
	}
	.name {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 6px;
	}
	.tag {
		padding: 0 6px;
		font-size: var(--fs-xs);
		line-height: 18px;
		font-weight: 500;
		color: var(--text-2);
		background: var(--surface-3);
		border-radius: var(--radius-sm);
	}
	/* Al llegar desde Estado (#copia-…), se lleva a la vista y se resalta. */
	.row.marked {
		background: var(--accent-soft);
		scroll-margin-top: calc(var(--header-h, 56px) + 16px);
	}
</style>
