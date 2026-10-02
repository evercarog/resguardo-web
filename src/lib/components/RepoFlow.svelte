<script lang="ts">
	import { ArrowRight, CircleAlert, CircleCheck, CircleDashed, Cloud, CloudOff, FolderOpen, ShieldAlert, ShieldCheck, TriangleAlert } from '@lucide/svelte';
	import InfoTip from '$lib/components/InfoTip.svelte';
	import PlaceIcon from '$lib/components/PlaceIcon.svelte';
	import RelTime from '$lib/components/RelTime.svelte';
	import { formatNumber } from '$lib/format';
	import { OFFSITE_PROVIDERS, lastCheck, offsiteScheduleLabel, placeOf, repoScheduleLabel, repoStatus } from '$lib/status';
	import type { Repo } from '$lib/types';

	// El camino de los datos (como en la app de escritorio): tus archivos →
	// el repositorio → la copia externa. Cada paso, con su estado y su hora.
	let { repo, now }: { repo: Repo; now: number } = $props();

	const status = $derived(repoStatus(repo, now));
	const at = $derived(lastCheck(repo).at);
	const place = $derived(placeOf(repo));
	const plans = $derived(repo.plans ?? []);
	const borrado = $derived(repo.protection?.items.find((i) => i.id === 'borrado') ?? null);
	const off = $derived(repo.maintenance?.offsite ?? null);
	const target = $derived(off ? (off.target_name ?? OFFSITE_PROVIDERS[off.provider] ?? 'Otra ubicación') : '');

	/** Tono del primer paso: cómo van las copias. */
	const sourceTone = $derived(
		status.level === 'failed' || status.level === 'overdue' ? 'bad' : status.level === 'late' ? 'warn' : status.level === 'ok' ? 'ok' : 'neutral'
	);
	const cloud = $derived.by(() => {
		if (!off) return { tone: 'neutral', text: 'Sin copia externa' };
		if (repo.offsite_hold) return { tone: 'bad', text: 'Subida frenada por un cambio inusual' };
		if (repo.offsite_run?.result === 'error') return { tone: 'bad', text: 'La última subida falló' };
		if (!repo.offsite_run) return { tone: 'warn', text: 'Todavía sin ninguna subida' };
		const up = new Date(repo.offsite_run.finished ?? repo.offsite_run.started).getTime();
		const local = repo.last_snapshot_at ? new Date(repo.last_snapshot_at).getTime() : null;
		return local === null || up >= local ? { tone: 'ok', text: 'Al día con el repositorio' } : { tone: 'warn', text: 'Pendiente de subir lo último' };
	});
</script>

<section class="card flow" aria-labelledby="t-flow">
	<h2 class="section-title" id="t-flow">Cómo se protegen tus datos</h2>
	<ol class="steps">
		<!-- 1. Tus archivos -->
		<li class="step tone-{sourceTone}">
			<span class="ic" aria-hidden="true"><FolderOpen size={18} /></span>
			<div class="body">
				<span class="k">Tus archivos</span>
				<strong>{plans.length ? plans.map((p) => p.name).join(', ') : 'Tus carpetas'}</strong>
				<span class="st">
					{#if sourceTone === 'ok'}<CircleCheck size={13} aria-hidden="true" />{:else if sourceTone === 'neutral'}<CircleDashed
							size={13}
							aria-hidden="true"
						/>{:else if sourceTone === 'warn'}<TriangleAlert size={13} aria-hidden="true" />{:else}<CircleAlert size={13} aria-hidden="true" />{/if}
					{#if at}Última copia <RelTime iso={new Date(at).toISOString()} {now} />{:else}Todavía sin copias{/if}
				</span>
			</div>
		</li>

		<li class="arrow" aria-hidden="true"><ArrowRight size={16} /><span>{repoScheduleLabel(repo)}</span></li>

		<!-- 2. El repositorio, en su destino -->
		<li class="step tone-{borrado?.state === 'ok' ? 'ok' : borrado?.state === 'bad' ? 'warn' : 'neutral'}">
			<span class="ic" aria-hidden="true"><PlaceIcon kind={place.kind} size={18} /></span>
			<div class="body">
				<span class="k">Repositorio <InfoTip term="repositorio" /></span>
				<strong>{repo.name}</strong>
				<span class="faint sub">{place.name}{repo.snapshots_count != null ? ` · ${formatNumber(repo.snapshots_count)} versiones` : ''}</span>
				<span class="st">
					{#if borrado?.state === 'ok'}<ShieldCheck size={13} aria-hidden="true" /> Protegido contra borrado
					{:else if borrado?.state === 'bad'}<ShieldAlert size={13} aria-hidden="true" /> Se puede borrar desde el equipo
					{:else}<CircleDashed size={13} aria-hidden="true" /> Protección contra borrado sin comprobar{/if}
					<InfoTip term="prot-borrado" />
				</span>
			</div>
		</li>

		<li class="arrow" class:off={!off} aria-hidden="true">
			<ArrowRight size={16} /><span>{off?.schedule ? offsiteScheduleLabel(off.schedule) : off ? 'subida programada' : ''}</span>
		</li>

		<!-- 3. La copia externa -->
		<li class="step tone-{cloud.tone}" class:dashed={!off}>
			<span class="ic" aria-hidden="true">{#if off}<Cloud size={18} />{:else}<CloudOff size={18} />{/if}</span>
			<div class="body">
				<span class="k">Copia externa <InfoTip term="prot-externa" /></span>
				<strong>{off ? target : 'Todavía no hay'}</strong>
				{#if off && repo.offsite_run}
					<span class="faint sub">Última subida <RelTime iso={repo.offsite_run.finished ?? repo.offsite_run.started} {now} /></span>
				{:else if !off}
					<span class="faint sub">Todas las versiones están en un solo lugar.</span>
				{/if}
				<span class="st">
					{#if cloud.tone === 'ok'}<CircleCheck size={13} aria-hidden="true" />{:else if cloud.tone === 'bad'}<CircleAlert
							size={13}
							aria-hidden="true"
						/>{:else if cloud.tone === 'warn'}<TriangleAlert size={13} aria-hidden="true" />{:else}<CircleDashed size={13} aria-hidden="true" />{/if}
					{cloud.text}
				</span>
			</div>
		</li>
	</ol>
</section>

<style>
	.flow {
		display: flex;
		flex-direction: column;
		gap: var(--sp-4);
		padding: var(--sp-5);
	}
	.steps {
		display: grid;
		grid-template-columns: minmax(0, 1fr) auto minmax(0, 1fr) auto minmax(0, 1fr);
		align-items: stretch;
		gap: var(--sp-2);
		margin: 0;
		padding: 0;
		list-style: none;
	}
	.step {
		display: flex;
		gap: var(--sp-3);
		min-width: 0;
		padding: var(--sp-4);
		background: var(--surface-2);
		border-radius: var(--radius-lg);
	}
	.step.dashed {
		background: transparent;
		border: 1px dashed var(--border-strong);
	}
	.ic {
		display: grid;
		flex: none;
		place-items: center;
		width: 36px;
		height: 36px;
		color: var(--text-2);
		background: var(--surface);
		border-radius: var(--radius);
	}
	.body {
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
	}
	.k {
		display: inline-flex;
		align-items: center;
		gap: 2px;
		font-size: var(--fs-xs);
		line-height: var(--lh-xs);
		font-weight: 500;
		color: var(--text-3);
	}
	strong {
		font-weight: 500;
		overflow-wrap: anywhere;
	}
	.sub {
		font-size: var(--fs-xs);
		line-height: var(--lh-xs);
		overflow-wrap: anywhere;
	}
	.st {
		display: block;
		margin-top: 4px;
		font-size: var(--fs-sm);
		line-height: var(--lh-sm);
		font-weight: 500;
		color: var(--tone);
	}
	.st :global(svg) {
		margin-right: 4px;
		vertical-align: -2px;
	}
	.tone-neutral .st {
		font-weight: 400;
		color: var(--text-3);
	}
	.arrow {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 4px;
		max-width: 120px;
		color: var(--text-3);
		text-align: center;
	}
	.arrow span {
		font-size: var(--fs-xs);
		line-height: var(--lh-xs);
	}
	.arrow.off {
		opacity: 0.5;
	}
	@media (max-width: 860px) {
		.steps {
			grid-template-columns: minmax(0, 1fr);
		}
		.arrow {
			flex-direction: row;
			justify-content: flex-start;
			max-width: none;
			padding-left: var(--sp-6);
		}
		.arrow :global(svg) {
			transform: rotate(90deg);
		}
	}
</style>
