<script lang="ts">
	import { CircleAlert, CirclePause, Cloud, CloudOff, LoaderCircle, TriangleAlert } from '@lucide/svelte';
	import DaySquares from '$lib/components/DaySquares.svelte';
	import ProtectionRing from '$lib/components/ProtectionRing.svelte';
	import RemoteBackup from '$lib/components/RemoteBackup.svelte';
	import { db } from '$lib/data.svelte';
	import RelTime from '$lib/components/RelTime.svelte';
	import StatusChip from '$lib/components/StatusChip.svelte';
	import TaskProgress from '$lib/components/TaskProgress.svelte';
	import { dayKey, formatBytes, formatDate, formatNumber, formatTime, startOfDay } from '$lib/format';
	import {
		OFFSITE_PROVIDERS,
		chipLevel,
		deviceOnline,
		elapsedLabel,
		nextExpected,
		pauseUntilLabel,
		protectionSummary,
		repoScheduleLabel,
		repoStatus,
		runningSince,
		taskRunning,
		type DayCell
	} from '$lib/status';
	import type { Device, Repo } from '$lib/types';

	// Tarjeta de un destino en Estado (diseño común): tranquila, cuatro datos como
	// mucho. Nombre y estado; lo que haya que saber ya (fallo, retraso, pausa,
	// copia en curso); última versión, próxima y versiones; la nube; la
	// protección compacta y los 14 días. El detalle está en la página del destino.
	let {
		repo,
		status,
		device,
		days,
		now
	}: { repo: Repo; status: ReturnType<typeof repoStatus>; device: Device | null; days: DayCell[] | null; now: number } = $props();

	const level = $derived(chipLevel(repo, status.level));
	const href = $derived(`/repo/${repo.device_id}/${encodeURIComponent(repo.repo_id)}`);
	const running = $derived(runningSince(repo, now));
	const task = $derived(taskRunning(repo, now));
	const next = $derived(status.pause.active ? null : nextExpected(repo, now));
	const off = $derived(repo.maintenance?.offsite ?? null);
	const prot = $derived(repo.protection ? protectionSummary(repo.protection) : null);
	/** «Copiar ahora»: solo si el equipo lo permite y está conectado. */
	const plans = $derived(repo.plans ?? []);
	const canRemote = $derived(!!device?.remote_backup_enabled && !!device && deviceOnline(device, now) && plans.length > 0);
	/** Alguna petición a distancia de este destino viva o de las últimas 24 h. */
	const hasRemote = $derived(
		db.commands.some(
			(c) =>
				c.device_id === repo.device_id &&
				c.repo_id === repo.repo_id &&
				(c.status === 'pending' || c.status === 'claimed' || now - new Date(c.finished_at ?? c.requested_at).getTime() < 86_400_000)
		)
	);

	/** La nube en una línea: dónde y cómo va. */
	const cloud = $derived.by(() => {
		if (!off) return { tone: 'neutral', text: 'Sin copia externa', where: '' };
		const where = off.target_name ?? OFFSITE_PROVIDERS[off.provider] ?? 'Otra ubicación';
		if (repo.offsite_hold) return { tone: 'bad', text: 'Subida frenada por un cambio inusual', where };
		if (repo.offsite_run?.result === 'error') return { tone: 'bad', text: 'La última subida falló', where };
		const up = repo.offsite_run?.finished ? new Date(repo.offsite_run.finished).getTime() : null;
		const local = repo.last_snapshot_at ? new Date(repo.last_snapshot_at).getTime() : null;
		if (up === null) return { tone: 'warn', text: 'Todavía sin ninguna subida', where };
		if (local === null || up >= local) return { tone: 'ok', text: 'Al día', where };
		return { tone: 'warn', text: `Pendiente · ${elapsedLabel((local - up) / 3_600_000)} por detrás`, where };
	});

	/** «hoy a las 17:00», «mañana a las 17:00» o la fecha (días de Bogotá). */
	function nextLabel(d: Date) {
		if (dayKey(d) === dayKey(now)) return `hoy, ${formatTime(d)}`;
		if (dayKey(d) === dayKey(startOfDay(now, 1))) return `mañana, ${formatTime(d)}`;
		return formatDate(d);
	}
</script>

<article class="card dest" class:held={!!repo.offsite_hold}>
	<header class="top">
		<div class="title">
			<h3><a {href}>{repo.name}</a></h3>
		</div>
		<StatusChip {level} />
	</header>

	<!-- Lo que hay que saber ya -->
	{#if running}
		<p class="alert tone-info"><span class="spin"><LoaderCircle size={14} aria-hidden="true" /></span> Copiando ahora · desde las {formatTime(running)}</p>
	{/if}
	{#if task}
		<TaskProgress {repo} {device} {now} />
	{/if}
	{#if repo.offsite_hold}
		<p class="alert tone-bad"><CloudOff size={14} aria-hidden="true" /> Subida a la nube frenada: hay un cambio inusual por revisar.</p>
	{/if}
	{#if status.level === 'failed' && repo.last_run?.message}
		<p class="alert tone-bad"><CircleAlert size={14} aria-hidden="true" /> {repo.last_run.message}</p>
	{:else if (status.level === 'late' || status.level === 'overdue') && status.since !== null}
		<p class="alert tone-{status.level === 'late' ? 'warn' : 'bad'}">
			<TriangleAlert size={14} aria-hidden="true" />
			{status.level === 'late' ? `${elapsedLabel(status.since - status.expected)} de retraso` : `Sin copias desde hace ${elapsedLabel(status.since)}`}
		</p>
	{/if}
	{#if status.pause.active}
		<p class="alert tone-paused"><CirclePause size={14} aria-hidden="true" /> Copias automáticas en pausa {pauseUntilLabel(status.pause.until)}</p>
	{/if}

	<dl class="facts">
		<div>
			<dt>Última versión</dt>
			<dd>
				{#if status.last}<RelTime iso={status.last} {now} />{:else}<span class="faint">Todavía ninguna</span>{/if}
			</dd>
			{#if status.unchangedAt}
				<dd class="sub">Revisada <RelTime iso={status.unchangedAt} {now} /> · sin cambios</dd>
			{:else if repo.last_data_added != null}
				<dd class="sub num">+{formatBytes(repo.last_data_added)}</dd>
			{/if}
		</div>
		<div>
			<dt>Próxima</dt>
			<dd title={next ? formatDate(next) : undefined}>{status.pause.active ? 'En pausa' : next ? nextLabel(next) : '—'}</dd>
			<dd class="sub">{repoScheduleLabel(repo)}</dd>
		</div>
		<div>
			<dt>Versiones</dt>
			<dd class="num">{repo.snapshots_count != null ? formatNumber(repo.snapshots_count) : '—'}</dd>
			<dd class="sub num">{repo.last_total_bytes != null ? `${formatBytes(repo.last_total_bytes)} protegidos` : 'Nada guardado todavía'}</dd>
		</div>
	</dl>

	<p class="cloud tone-{cloud.tone}">
		{#if off}<Cloud size={14} aria-hidden="true" />{:else}<CloudOff size={14} aria-hidden="true" />{/if}
		<span class="cloud-text">
			{#if cloud.where}<span class="faint">Nube · {cloud.where} ·</span>{/if}
			<span class="state">{cloud.text}</span>
		</span>
	</p>

	{#if canRemote || hasRemote}
		<div class="remote">
			{#if canRemote && plans.length === 1}
				<RemoteBackup {repo} planId={plans[0].id} planName={plans[0].name} {device} {now} />
			{:else}
				{#if canRemote}<a class="btn btn-sm" href="{href}#copias">Copiar ahora…</a>{/if}
				{#each plans as p (p.id)}<RemoteBackup {repo} planId={p.id} planName={p.name} {device} {now} statusOnly />{/each}
			{/if}
		</div>
	{/if}

	<footer class="foot">
		{#if repo.protection && prot}
			<a class="prot" href="{href}#proteccion" title={repo.protection.items.filter((i) => i.state !== 'ok').map((i) => `${i.label}: ${i.detail ?? ''}`).join('\n')}>
				<ProtectionRing protection={repo.protection} />
				<span>Protección <strong class="num">{repo.protection.score} de {repo.protection.total}</strong>{prot.issues ? ` · ${prot.issues} por revisar` : ''}</span>
			</a>
		{:else}
			<span></span>
		{/if}
		{#if days}
			<DaySquares {days} size="mini" label="Últimos 14 días de {repo.name}" />
		{/if}
	</footer>
</article>

<style>
	.dest {
		display: flex;
		flex-direction: column;
		gap: var(--sp-4);
		min-width: 0;
		padding: var(--sp-5);
	}
	.dest:hover {
		border-color: var(--border-strong);
	}
	.dest.held {
		border-color: color-mix(in srgb, var(--bad) 30%, transparent);
	}
	.top {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: var(--sp-3);
	}
	.title {
		min-width: 0;
	}
	h3 {
		font-size: var(--fs-h2);
		line-height: var(--lh-h2);
		font-weight: 600;
		letter-spacing: -0.01em;
		overflow-wrap: anywhere;
	}
	h3 a {
		color: var(--text-1);
	}
	.alert {
		display: flex;
		align-items: flex-start;
		gap: 8px;
		margin: calc(-1 * var(--sp-1)) 0 0;
		font-size: var(--fs-sm);
		line-height: var(--lh-sm);
		color: var(--tone);
		overflow-wrap: anywhere;
	}
	.alert :global(svg) {
		flex: none;
		margin-top: 2px;
	}
	.facts {
		display: grid;
		grid-template-columns: repeat(3, minmax(0, 1fr));
		gap: var(--sp-4);
		margin: 0;
	}
	.facts > div {
		min-width: 0;
	}
	dt {
		font-size: var(--fs-xs);
		line-height: var(--lh-xs);
		font-weight: 500;
		color: var(--text-3);
	}
	dd {
		margin: 2px 0 0;
		font-weight: 500;
	}
	dd.sub {
		margin-top: 0;
		font-size: var(--fs-xs);
		line-height: var(--lh-xs);
		font-weight: 400;
		color: var(--text-3);
		overflow-wrap: anywhere;
	}
	.cloud {
		display: flex;
		align-items: flex-start;
		gap: 8px;
		padding-top: var(--sp-4);
		font-size: var(--fs-sm);
		line-height: var(--lh-sm);
		border-top: 1px solid var(--border);
	}
	.cloud :global(svg) {
		flex: none;
		margin-top: 2px;
		color: var(--text-3);
	}
	.cloud .state {
		font-weight: 500;
		color: var(--tone);
	}
	.cloud.tone-neutral .state {
		font-weight: 400;
		color: var(--text-3);
	}
	.remote {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--sp-2) var(--sp-3);
		margin-top: calc(-1 * var(--sp-2));
	}
	.foot {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		justify-content: space-between;
		gap: var(--sp-2) var(--sp-4);
		margin-top: auto;
	}
	.prot {
		display: inline-flex;
		align-items: center;
		gap: 8px;
		font-size: var(--fs-sm);
		line-height: var(--lh-sm);
		color: var(--text-2);
	}
	.prot strong {
		font-weight: 600;
		color: var(--text-1);
	}
	@media (max-width: 520px) {
		.facts {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
		.facts > div:last-child {
			grid-column: 1 / -1;
		}
	}
</style>
