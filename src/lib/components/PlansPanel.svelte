<script lang="ts">
	import { CalendarClock, CircleAlert, CircleCheck, Hand, TriangleAlert } from '@lucide/svelte';
	import { formatDate, formatRelative } from '$lib/format';
	import { planScheduleLabel } from '$lib/status';
	import type { PlanInfo } from '$lib/types';

	// Planes de copia del repositorio, tal como los informa el equipo.
	let { plans, now }: { plans: PlanInfo[]; now: number } = $props();
</script>

{#if plans.length}
	<section class="card plans">
		<h2>Copias que se guardan aquí</h2>
		<div class="rows">
			{#each plans as p (p.id)}
				<div class="row" class:off={!p.schedule}>
					<span class="ic">
						{#if p.schedule}<CalendarClock size={16} />{:else}<Hand size={16} />{/if}
					</span>
					<div class="what">
						<div class="name">
							<strong>{p.name}</strong>
							{#each p.tags ?? [] as t}<span class="tag">{t}</span>{/each}
						</div>
						<span class="faint when">{p.schedule ? planScheduleLabel(p.schedule) : 'Solo a mano'}</span>
					</div>
					<div class="state">
						{#if p.last_run}
							{@const run = p.last_run}
							<span class="res res-{run.result}" title={run.finished ? formatDate(run.finished) : ''}>
								{#if run.result === 'ok'}<CircleCheck size={13} />{:else if run.result === 'warning'}<TriangleAlert
										size={13}
									/>{:else}<CircleAlert size={13} />{/if}
								{formatRelative(run.finished ?? run.started, now)}
							</span>
							{#if run.result !== 'ok' && run.message}<span class="msg">{run.message}</span>{/if}
						{:else}
							<span class="faint">todavía ninguna</span>
						{/if}
					</div>
				</div>
			{/each}
		</div>
	</section>
{/if}

<style>
	.plans {
		display: flex;
		flex-direction: column;
		gap: 12px;
		padding: 18px 20px;
	}
	h2 {
		font-size: 16px;
		font-weight: 650;
	}
	.rows {
		display: flex;
		flex-direction: column;
	}
	.row {
		display: grid;
		grid-template-columns: auto minmax(0, 1fr) minmax(0, 1.1fr);
		align-items: center;
		gap: 12px;
		padding: 10px 0;
		border-top: 1px solid var(--border);
	}
	.row:first-child {
		border-top: none;
		padding-top: 0;
	}
	.row.off .ic {
		color: var(--text-3);
		background: var(--surface-3);
	}
	.ic {
		display: grid;
		place-items: center;
		width: 32px;
		height: 32px;
		border-radius: 9px;
		color: var(--accent-soft-text, var(--accent));
		background: var(--accent-soft, var(--surface-3));
	}
	.what {
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
		font-size: 13.5px;
	}
	.name {
		display: flex;
		align-items: center;
		flex-wrap: wrap;
		gap: 4px 6px;
		min-width: 0;
	}
	.name strong {
		overflow-wrap: anywhere;
	}
	.tag {
		padding: 0 8px;
		font-size: 11px;
		font-weight: 550;
		line-height: 18px;
		border-radius: 999px;
		background: var(--accent-soft);
		color: var(--accent-soft-text);
	}
	.when {
		font-size: 12px;
	}
	.when::first-letter {
		text-transform: uppercase;
	}
	.state {
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		gap: 2px;
		min-width: 0;
		font-size: 12.5px;
		text-align: right;
	}
	.res {
		display: inline-flex;
		align-items: center;
		gap: 4px;
		font-weight: 600;
	}
	.res-ok {
		color: var(--success);
	}
	.res-warning {
		color: var(--warn);
	}
	.res-error {
		color: var(--danger);
	}
	.msg {
		font-size: 11.5px;
		color: var(--text-2);
		overflow: hidden;
		text-overflow: ellipsis;
		display: -webkit-box;
		-webkit-line-clamp: 2;
		line-clamp: 2;
		-webkit-box-orient: vertical;
	}
	@media (max-width: 640px) {
		.row {
			grid-template-columns: auto minmax(0, 1fr);
		}
		.state {
			grid-column: 2;
			align-items: flex-start;
			text-align: left;
		}
	}
</style>
