<script lang="ts">
	import { ArchiveRestore, CloudUpload, LoaderCircle, ShieldCheck } from '@lucide/svelte';
	import RunResult from '$lib/components/RunResult.svelte';
	import { OFFSITE_PROVIDERS as PROVIDERS, offsiteScheduleLabel, offsiteVerifySummary, restoreTestLabel, scheduleLabel, taskProgress, verifyModeLabel } from '$lib/status';
	import type { Repo, TaskRun } from '$lib/types';

	// Verificación y copia externa del repositorio, tal como las informa el equipo.
	let { repo, now }: { repo: Repo; now: number } = $props();

	const m = $derived(repo.maintenance);
	/** Tarea en curso (una sin noticias en 12 h se da por cortada). */
	const progress = $derived(taskProgress(repo, now));
	const running = $derived(progress?.task ?? null);
	const cloudVerify = $derived(offsiteVerifySummary(repo, now));
</script>

{#snippet result(run: TaskRun | null)}
	{#if run}
		<RunResult {run} {now} />
		{#if run.message}<span class="msg">{run.message}</span>{/if}
	{:else}
		<span class="faint">todavía ninguna</span>
	{/if}
{/snippet}

{#if m?.verify || m?.offsite || m?.restore_test}
	<section class="card panel maint" aria-labelledby="t-maint">
		<div class="panel-head"><h2 class="section-title" id="t-maint">Mantenimiento</h2></div>
		<div class="rows">
			<div class="row" class:off={!m?.verify}>
				<span class="ic" aria-hidden="true"><ShieldCheck size={16} /></span>
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
						<span class="live"><span class="spin"><LoaderCircle size={14} /></span>{running.stage || 'Verificando…'}{progress?.percent != null ? ` · ${Math.floor(progress.percent)} %` : ''}</span>
					{:else if m?.verify}
						{@render result(repo.verify_run)}
					{/if}
				</div>
			</div>

			<div class="row" class:off={!m?.restore_test}>
				<span class="ic" aria-hidden="true"><ArchiveRestore size={16} /></span>
				<div class="what">
					<strong>Prueba de restauración</strong>
					<span class="faint">
						{#if m?.restore_test}
							{m.restore_test.schedule ? scheduleLabel(m.restore_test.schedule) : 'programada'} · {restoreTestLabel(m.restore_test)}
						{:else}
							No programada: nadie comprueba que las copias se puedan recuperar
						{/if}
					</span>
				</div>
				<div class="state">
					{#if running?.kind === 'restore_test'}
						<span class="live"
							><span class="spin"><LoaderCircle size={14} /></span>{running.stage || 'Restaurando archivos de prueba…'}{progress?.percent != null
								? ` · ${Math.floor(progress.percent)} %`
								: ''}</span
						>
					{:else if m?.restore_test}
						{@render result(repo.restore_test_run ?? null)}
					{/if}
				</div>
			</div>

			<div class="row" class:off={!m?.offsite}>
				<span class="ic" aria-hidden="true"><CloudUpload size={16} /></span>
				<div class="what">
					<strong>Copia externa</strong>
					<span class="faint">
						{#if m?.offsite}
							{m.offsite.target_name ? `«${m.offsite.target_name}»` : (PROVIDERS[m.offsite.provider] ?? 'Otra ubicación')} · {m.offsite.schedule ? offsiteScheduleLabel(m.offsite.schedule) : 'programada'}{m
								.offsite.retention
								? ' · con retención'
								: ''}
						{:else}
							No configurada: todas las versiones están en un solo lugar
						{/if}
					</span>
					{#if cloudVerify}
						<span class="faint cv" class:bad={cloudVerify.result === 'error'}>
							{cloudVerify.text}{#if cloudVerify.rotation}<br />{cloudVerify.rotation}{/if}
						</span>
						{#if cloudVerify.message}<span class="msg">{cloudVerify.message}</span>{/if}
					{/if}
				</div>
				<div class="state">
					{#if running?.kind === 'offsite' || running?.kind === 'verify_offsite'}
						<span class="live"><span class="spin"><LoaderCircle size={14} /></span>{running.stage || (running.kind === 'offsite' ? 'Subiendo…' : 'Verificando la nube…')}{progress?.percent != null ? ` · ${Math.floor(progress.percent)} %` : ''}</span>
					{:else if m?.offsite}
						{@render result(repo.offsite_run)}
					{/if}
				</div>
			</div>
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
	.live {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		font-weight: 500;
		color: var(--info);
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

	.cv {
		margin-top: 2px;
	}
	.cv.bad {
		color: var(--bad);
	}
</style>
