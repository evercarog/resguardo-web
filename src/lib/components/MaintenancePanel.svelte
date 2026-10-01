<script lang="ts">
	import { CircleAlert, CircleCheck, CloudUpload, LoaderCircle, ShieldCheck, TriangleAlert } from '@lucide/svelte';
	import { formatDate, formatRelative } from '$lib/format';
	import { OFFSITE_PROVIDERS as PROVIDERS, offsiteScheduleLabel, scheduleLabel, taskProgress, verifyModeLabel } from '$lib/status';
	import type { Repo, TaskRun } from '$lib/types';

	// Verificación y copia externa del repositorio, tal como las informa el equipo.
	let { repo, now }: { repo: Repo; now: number } = $props();

	const m = $derived(repo.maintenance);
	/** Tarea en curso (una sin noticias en 12 h se da por cortada). */
	const progress = $derived(taskProgress(repo, now));
	const running = $derived(progress?.task ?? null);
</script>

{#snippet result(run: TaskRun | null)}
	{#if run}
		<span class="res res-{run.result}" title={run.finished ? formatDate(run.finished) : ''}>
			{#if run.result === 'ok'}<CircleCheck size={13} />{:else if run.result === 'warning'}<TriangleAlert size={13} />{:else}<CircleAlert size={13} />{/if}
			{run.finished ? formatRelative(run.finished, now) : '—'}
		</span>
		{#if run.message}<span class="msg">{run.message}</span>{/if}
	{:else}
		<span class="faint">todavía ninguna</span>
	{/if}
{/snippet}

{#if m?.verify || m?.offsite}
	<section class="card maint">
		<h2>Mantenimiento</h2>
		<div class="rows">
			<div class="row" class:off={!m?.verify}>
				<span class="ic"><ShieldCheck size={16} /></span>
				<div class="what">
					<strong>Verificación</strong>
					<span class="faint">
						{#if m?.verify}
							{m.verify.schedule ? scheduleLabel(m.verify.schedule) : 'programada'}
							· {verifyModeLabel(m.verify, now)}
						{:else}
							No programada
						{/if}
					</span>
				</div>
				<div class="state">
					{#if running?.kind === 'verify'}
						<span class="live"><span class="spin"><LoaderCircle size={13} /></span>{running.stage || 'Verificando…'}{progress?.percent != null ? ` · ${Math.floor(progress.percent)} %` : ''}</span>
					{:else if m?.verify}
						{@render result(repo.verify_run)}
					{/if}
				</div>
			</div>

			<div class="row" class:off={!m?.offsite}>
				<span class="ic"><CloudUpload size={16} /></span>
				<div class="what">
					<strong>Copia externa</strong>
					<span class="faint">
						{#if m?.offsite}
							{m.offsite.target_name ? `«${m.offsite.target_name}»` : (PROVIDERS[m.offsite.provider] ?? 'Otra ubicación')} · {m.offsite.schedule ? offsiteScheduleLabel(m.offsite.schedule) : 'programada'}{m
								.offsite.retention
								? ' · con retención'
								: ''}
						{:else}
							No configurada: todas las copias están en un solo lugar
						{/if}
					</span>
				</div>
				<div class="state">
					{#if running?.kind === 'offsite'}
						<span class="live"><span class="spin"><LoaderCircle size={13} /></span>{running.stage || 'Subiendo…'}{progress?.percent != null ? ` · ${Math.floor(progress.percent)} %` : ''}</span>
					{:else if m?.offsite}
						{@render result(repo.offsite_run)}
					{/if}
				</div>
			</div>
		</div>
	</section>
{/if}

<style>
	.maint {
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
		gap: 1px;
		min-width: 0;
		font-size: 13.5px;
	}
	.what .faint {
		font-size: 12px;
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
	.live {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		color: var(--accent);
		font-weight: 600;
	}
	.spin {
		display: grid;
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
