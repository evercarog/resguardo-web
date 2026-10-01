<script lang="ts">
	import { onMount } from 'svelte';
	import { CalendarClock, Hand } from '@lucide/svelte';
	import RunResult from '$lib/components/RunResult.svelte';
	import { planScheduleLabel } from '$lib/status';
	import type { PlanInfo } from '$lib/types';

	// Planes de copia del repositorio, tal como los informa el equipo.
	let { plans, now }: { plans: PlanInfo[]; now: number } = $props();

	/** Copia señalada desde Estado (#copia-<id>): se lleva a la vista y se resalta. */
	let marked = $state('');
	onMount(() => {
		const id = decodeURIComponent(location.hash.replace(/^#copia-/, ''));
		if (!location.hash.startsWith('#copia-') || !plans.some((p) => p.id === id)) return;
		marked = id;
		requestAnimationFrame(() => document.getElementById(`copia-${id}`)?.scrollIntoView({ block: 'center' }));
	});
</script>

{#if plans.length}
	<section class="card panel plans" aria-labelledby="t-plans">
		<div class="panel-head"><h2 class="section-title" id="t-plans">Copias que se guardan aquí</h2></div>
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
