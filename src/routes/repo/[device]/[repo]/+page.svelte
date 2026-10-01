<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/state';
	import { ArrowLeft, CircleAlert, CirclePause, CloudOff, History, LoaderCircle, X } from '@lucide/svelte';
	import ActivityChart from '$lib/components/ActivityChart.svelte';
	import DaySquares from '$lib/components/DaySquares.svelte';
	import MaintenancePanel from '$lib/components/MaintenancePanel.svelte';
	import PlansPanel from '$lib/components/PlansPanel.svelte';
	import ProtectionPanel from '$lib/components/ProtectionPanel.svelte';
	import RelTime from '$lib/components/RelTime.svelte';
	import StatusChip from '$lib/components/StatusChip.svelte';
	import TaskProgress from '$lib/components/TaskProgress.svelte';
	import { db, friendlyError, loadAll } from '$lib/data.svelte';
	import { dayKey, formatBytes, formatDate, formatDay, formatDayShort, formatDuration, formatNumber, formatTime, fromDayKey, startOfDay } from '$lib/format';
	import {
		HOLD_ADVICE,
		chipLevel,
		dayState,
		dayStateLabel,
		holdSummary,
		kindLabel,
		pauseUntilLabel,
		repoScheduleLabel,
		repoStatus,
		runningSince,
		taskRunning,
		type DayCell
	} from '$lib/status';
	import { supabase } from '$lib/supabase';
	import type { SnapshotRow } from '$lib/types';

	const deviceId = $derived(page.params.device ?? '');
	const repoId = $derived(page.params.repo ?? '');

	let snapshots = $state<SnapshotRow[]>([]);
	/** Copias de los últimos 60 días por día (AAAA-MM-DD en Bogotá): sin cambios, avisos y fallos. */
	let runDays = $state(new Map<string, { same: boolean; failed: boolean; warned: boolean }>());
	let loading = $state(true);
	let error = $state('');
	let day = $state<string | null>(null);
	/** Reloj para que el estado («Al día», «Con retraso»…) se actualice solo. */
	let now = $state(Date.now());

	const repo = $derived(db.repos.find((r) => r.device_id === deviceId && r.repo_id === repoId) ?? null);
	const device = $derived(db.devices.find((d) => d.id === deviceId) ?? null);
	const status = $derived(repo ? repoStatus(repo, now) : null);
	const running = $derived(repo ? runningSince(repo, now) : null);

	onMount(() => {
		const t = setInterval(() => (now = Date.now()), 30_000);
		load();
		return () => clearInterval(t);
	});

	async function load() {
		if (!db.loaded) await loadAll();
		const { data, error: e } = await supabase
			.from('snapshots')
			.select('*')
			.eq('device_id', deviceId)
			.eq('repo_id', repoId)
			.order('time', { ascending: false })
			.limit(500);
		if (e) error = friendlyError(e.message);
		else snapshots = data as SnapshotRow[];
		loading = false;
		// Copias de los últimos 60 días (sin cambios, avisos, fallos). Si falla, solo se pintan las versiones.
		const since = startOfDay(Date.now(), -60).toISOString();
		const { data: runs } = await supabase
			.from('runs')
			.select('*')
			.eq('device_id', deviceId)
			.eq('repo_id', repoId)
			.gte('started_at', since)
			.limit(3000);
		const out = new Map<string, { same: boolean; failed: boolean; warned: boolean }>();
		for (const x of (runs ?? []) as { started_at: string; finished_at: string | null; result: string; unchanged?: boolean }[]) {
			const k = dayKey(x.finished_at ?? x.started_at);
			const v = out.get(k) ?? { same: false, failed: false, warned: false };
			if (x.result === 'error') v.failed = true;
			else if (x.result === 'warning') v.warned = true;
			else if (x.unchanged) v.same = true;
			out.set(k, v);
		}
		runDays = out;
	}

	const withDuration = $derived(snapshots.filter((s) => s.duration_s != null));
	const avgDuration = $derived(withDuration.length ? withDuration.reduce((n, s) => n + (s.duration_s ?? 0), 0) / withDuration.length : null);
	const avgAdded = $derived(snapshots.length ? snapshots.reduce((n, s) => n + (s.data_added ?? 0), 0) / snapshots.length : null);

	/** Últimos 60 días (de hace 59 a hoy), con su resultado. */
	const days = $derived.by<DayCell[]>(() => {
		const counts = new Map<string, number>();
		for (const s of snapshots) counts.set(dayKey(s.time), (counts.get(dayKey(s.time)) ?? 0) + 1);
		return Array.from({ length: 60 }, (_, i) => {
			const date = startOfDay(now, -(59 - i));
			const key = dayKey(date);
			const n = counts.get(key) ?? 0;
			const r = runDays.get(key) ?? { same: false, failed: false, warned: false };
			const state = dayState({ n, ...r });
			return { key, date, n, state, title: `${formatDayShort(date)}: ${dayStateLabel(state, n)}` };
		});
	});

	const shown = $derived(day ? snapshots.filter((s) => dayKey(s.time) === day) : snapshots);
	const groups = $derived.by(() => {
		const out: { day: string; items: SnapshotRow[] }[] = [];
		for (const s of shown.slice(0, 200)) {
			const label = formatDay(s.time);
			if (out.at(-1)?.day === label) out.at(-1)!.items.push(s);
			else out.push({ day: label, items: [s] });
		}
		return out;
	});
</script>

<svelte:head><title>{repo?.name ?? 'Destino'} · Resguardo</title></svelte:head>

<div class="page">
	<a class="back" href="/"><ArrowLeft size={14} aria-hidden="true" /> Estado</a>

	{#if !db.loaded && db.error}
		<div class="notice notice-danger" role="alert"><CircleAlert size={16} /><p>{db.error}</p></div>
	{:else if !db.loaded}
		<!-- Esqueleto con la forma de la página -->
		<div class="skel-head" aria-hidden="true">
			<span class="skel sk-title"></span>
			<span class="skel sk-sub"></span>
		</div>
		<div class="card stats" aria-hidden="true">
			{#each { length: 4 } as _}
				<div class="stat"><span class="skel sk-label"></span><span class="skel sk-value"></span></div>
			{/each}
		</div>
		<div class="card block" aria-hidden="true"><span class="skel sk-block"></span></div>
		<span class="sr-only" role="status">Cargando…</span>
	{:else if !repo}
		<div class="empty-state">
			<History size={32} strokeWidth={1.5} />
			<p>Este destino ya no existe o el equipo todavía no lo ha informado.</p>
			<a class="btn btn-primary" href="/">Volver al estado</a>
		</div>
	{:else}
		<header class="page-head">
			<div class="htext">
				<h1 class="page-title">{repo.name}</h1>
				<p class="page-sub">
					{device?.name ?? 'Equipo'} · {kindLabel(repo.kind)}{repo.host ? ` · ${repo.host}` : ''} · {repoScheduleLabel(repo)}
				</p>
			</div>
			{#if status}<StatusChip level={chipLevel(repo, status.level)} />{/if}
		</header>

		{#if repo.offsite_hold}
			<div class="notice notice-danger hold" role="alert">
				<CloudOff size={16} />
				<div>
					<p><strong>Cambio inusual: la subida a la nube está frenada.</strong> {holdSummary(repo.offsite_hold, now)}</p>
					<p class="advice">{HOLD_ADVICE}</p>
				</div>
			</div>
		{/if}

		{#if status?.pause.active}
			<div class="notice tone-paused" role="status">
				<CirclePause size={16} />
				<p>
					<strong>Copias automáticas en pausa</strong>
					{pauseUntilLabel(status.pause.until)}{#if status.pause.since}<span class="faint"> · desde el {formatDate(status.pause.since)}</span>{/if}.
					Mientras tanto no se avisa de retrasos. Puedes reanudarlas desde Resguardo, en el equipo.
				</p>
			</div>
		{/if}

		{#if running}
			<div class="notice notice-info" role="status">
				<span class="spin"><LoaderCircle size={16} /></span>
				<p><strong>Copia automática en curso</strong> desde las {formatTime(running)}. El resultado aparecerá aquí en cuanto termine.</p>
			</div>
		{/if}

		{#if taskRunning(repo, now)}
			<div class="card taskbox"><TaskProgress {repo} {device} {now} /></div>
		{/if}

		<!-- Cifras -->
		<div class="card stats">
			<div class="stat">
				<span class="label">Última versión</span>
				<strong class="value">{#if status?.last}<RelTime iso={status.last} {now} capitalize />{:else}—{/if}</strong>
				<span class="sub">
					{#if status?.unchangedAt}Revisada <RelTime iso={status.unchangedAt} {now} /> · sin cambios{:else if status?.last}{formatDate(status.last)}{/if}
				</span>
			</div>
			<div class="stat">
				<span class="label">Versiones</span>
				<strong class="value num">{repo.snapshots_count != null ? formatNumber(repo.snapshots_count) : '—'}</strong>
				<span class="sub">guardadas en este destino</span>
			</div>
			<div class="stat">
				<span class="label">Tamaño protegido</span>
				<strong class="value num">{formatBytes(repo.last_total_bytes)}</strong>
				<span class="sub">en la última versión</span>
			</div>
			<div class="stat">
				<span class="label">Duración media</span>
				<strong class="value num">{avgDuration != null ? formatDuration(avgDuration) : '—'}</strong>
				<span class="sub num">{avgAdded != null ? `+${formatBytes(avgAdded)} por versión` : ''}</span>
			</div>
		</div>

		<ProtectionPanel {repo} {now} />

		{#if repo.plans?.length}<PlansPanel {repo} {device} {now} />{/if}

		<MaintenancePanel {repo} {now} />

		{#if error}<div class="notice notice-danger" role="alert"><CircleAlert size={16} /><p>{error}</p></div>{/if}

		<!-- Actividad y versiones -->
		<section class="card block" aria-labelledby="t-actividad">
			<div class="section-head">
				<h2 class="section-title" id="t-actividad">Actividad <span class="count">· últimos 60 días</span></h2>
			</div>
			<DaySquares {days} selected={day} onselect={(k) => (day = k)} label="Actividad de los últimos 60 días: toca un día con versiones para verlas" />
			<p class="legend">
				<span><i class="lg s-data"></i>Con versión</span>
				<span><i class="lg s-same"></i>Sin cambios</span>
				<span><i class="lg s-warn"></i>Con avisos</span>
				<span><i class="lg s-bad"></i>Falló</span>
				<span><i class="lg s-none"></i>Sin copia</span>
			</p>
			{#if snapshots.length >= 2}
				<div class="charts">
					<ActivityChart title="Datos nuevos por versión" items={snapshots} value={(s) => s.data_added} format={(v) => formatBytes(v)} />
					<ActivityChart title="Duración por versión" items={snapshots} value={(s) => s.duration_s} format={(v) => formatDuration(v)} />
				</div>
			{/if}
		</section>

		<section class="card block" aria-labelledby="t-versiones">
			<div class="section-head">
				<h2 class="section-title" id="t-versiones">
					Versiones <span class="count num">· {formatNumber(snapshots.length)} {snapshots.length === 1 ? 'más reciente' : 'más recientes'}</span>
				</h2>
				{#if day}
					<button class="btn btn-sm" onclick={() => (day = null)}>{formatDayShort(fromDayKey(day))} <X size={14} aria-label="Quitar el filtro" /></button>
				{/if}
			</div>

			{#if loading}
				<span class="skel sk-block" aria-hidden="true"></span>
			{:else if snapshots.length === 0 && !error}
				<div class="empty-state small-empty">
					<History size={32} strokeWidth={1.5} />
					<p>La lista de versiones llegará con el próximo informe del equipo.</p>
				</div>
			{:else}
				<div class="table-wrap">
					<table class="versions">
						<thead>
							<tr>
								<th scope="col">Hora</th>
								<th scope="col">Versión</th>
								<th scope="col" class="hide-sm">Archivos</th>
								<th scope="col" class="hide-sm">Copia</th>
								<th scope="col" class="r">Tamaño</th>
								<th scope="col" class="r">Datos nuevos</th>
							</tr>
						</thead>
						{#each groups as g (g.day)}
							<tbody>
								<tr class="dayrow"><th scope="rowgroup" colspan="6">{g.day}</th></tr>
								{#each g.items as s (s.snapshot_id)}
									<tr>
										<td class="num" title={formatDate(s.time)}>
											{formatTime(s.time)}{#if s.duration_s != null}<span class="faint dur"> · {formatDuration(s.duration_s)}</span>{/if}
										</td>
										<td><span class="mono id" title="Versión {s.snapshot_id}">{s.snapshot_id.slice(0, 8)}</span></td>
										<td class="hide-sm num faint">
											{#if s.files_new != null}{formatNumber(s.files_new)} nuevos · {formatNumber(s.files_changed ?? 0)} modif.{/if}
										</td>
										<td class="hide-sm">{#each s.tags ?? [] as t}<span class="tag">{t}</span>{/each}</td>
										<td class="r num">{formatBytes(s.total_bytes)}</td>
										<td class="r num added">{s.data_added != null ? `+${formatBytes(s.data_added)}` : '—'}</td>
									</tr>
								{/each}
							</tbody>
						{/each}
					</table>
				</div>
				{#if shown.length > 200}<p class="legend">Se muestran las 200 más recientes.</p>{/if}
			{/if}
		</section>
	{/if}
</div>

<style>
	.page {
		display: flex;
		flex-direction: column;
		gap: var(--sp-6);
	}
	.page-head {
		margin-bottom: 0;
	}
	.back {
		display: inline-flex;
		align-items: center;
		align-self: flex-start;
		gap: 6px;
		margin-bottom: calc(-1 * var(--sp-3));
		font-size: var(--fs-sm);
		font-weight: 500;
		color: var(--text-2);
	}
	.back:hover {
		color: var(--text-1);
		text-decoration: none;
	}
	.htext {
		min-width: 0;
	}
	.htext h1 {
		overflow-wrap: anywhere;
	}
	.hold > div {
		display: flex;
		flex-direction: column;
		gap: 6px;
	}
	.advice {
		color: var(--text-2) !important;
	}
	.taskbox {
		padding: var(--sp-4) var(--sp-5);
	}
	/* Cifras: un panel con separadores finos (cuatro como mucho). */
	.stats {
		display: grid;
		grid-template-columns: repeat(4, minmax(0, 1fr));
	}
	.stat {
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
		padding: var(--sp-5);
	}
	.stat + .stat {
		border-left: 1px solid var(--border);
	}
	.label {
		font-size: var(--fs-xs);
		line-height: var(--lh-xs);
		font-weight: 500;
		color: var(--text-3);
	}
	.value {
		font-size: var(--fs-stat);
		line-height: var(--lh-stat);
		font-weight: 600;
		letter-spacing: -0.02em;
		font-variant-numeric: tabular-nums;
	}
	.sub {
		font-size: var(--fs-xs);
		line-height: var(--lh-xs);
		color: var(--text-3);
	}
	.block {
		display: flex;
		flex-direction: column;
		gap: var(--sp-4);
		padding: var(--sp-5);
	}
	.block .section-head {
		margin-bottom: 0;
	}
	.legend {
		display: flex;
		flex-wrap: wrap;
		gap: 4px var(--sp-4);
		font-size: var(--fs-xs);
		line-height: var(--lh-xs);
		color: var(--text-3);
	}
	.legend span {
		display: inline-flex;
		align-items: center;
		gap: 6px;
	}
	.lg {
		display: inline-block;
		width: 10px;
		height: 10px;
		border-radius: 2px;
		background: var(--surface-3);
	}
	.lg.s-data {
		background: color-mix(in srgb, var(--ok) 85%, transparent);
	}
	.lg.s-same {
		background: color-mix(in srgb, var(--ok) 45%, transparent);
	}
	.lg.s-warn {
		background: var(--warn);
	}
	.lg.s-bad {
		background: var(--bad);
	}
	.charts {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: var(--sp-6);
		padding-top: var(--sp-4);
		border-top: 1px solid var(--border);
	}
	/* Tabla de versiones: filas de 40–44 px y separadores finos. */
	.table-wrap {
		margin: 0 calc(-1 * var(--sp-5));
		overflow-x: auto;
	}
	.versions {
		width: 100%;
		border-collapse: collapse;
		font-size: var(--fs-sm);
		line-height: var(--lh-sm);
	}
	.versions th,
	.versions td {
		height: 40px;
		padding: 0 var(--sp-3);
		text-align: left;
		white-space: nowrap;
		border-bottom: 1px solid var(--border);
	}
	.versions th:first-child,
	.versions td:first-child {
		padding-left: var(--sp-5);
	}
	.versions th:last-child,
	.versions td:last-child {
		padding-right: var(--sp-5);
	}
	.versions thead th {
		height: 32px;
		font-size: var(--fs-xs);
		font-weight: 500;
		color: var(--text-3);
	}
	.versions tbody tr:not(.dayrow):hover {
		background: var(--surface-2);
	}
	.dayrow th {
		height: 32px;
		font-size: var(--fs-xs);
		font-weight: 600;
		color: var(--text-2);
		background: var(--bg-subtle);
	}
	.r {
		text-align: right !important;
	}
	.id {
		color: var(--text-2);
	}
	.dur {
		font-size: var(--fs-xs);
	}
	.added {
		color: var(--text-2);
	}
	.tag {
		display: inline-block;
		margin-right: 4px;
		padding: 0 6px;
		font-size: var(--fs-xs);
		line-height: 18px;
		font-weight: 500;
		color: var(--text-2);
		background: var(--surface-3);
		border-radius: var(--radius-sm);
	}
	.small-empty {
		padding: var(--sp-8) var(--sp-4);
	}
	/* Esqueletos */
	.skel-head {
		display: flex;
		flex-direction: column;
		gap: 8px;
	}
	.sk-title {
		width: 260px;
		max-width: 70%;
		height: 26px;
	}
	.sk-sub {
		width: 380px;
		max-width: 90%;
		height: 14px;
	}
	.sk-label {
		width: 60%;
		height: 12px;
	}
	.sk-value {
		width: 45%;
		height: 24px;
		margin-top: 6px;
	}
	.sk-block {
		height: 160px;
	}
	@media (max-width: 860px) {
		.stats {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
		.stat:nth-child(3) {
			border-left: none;
		}
		.stat:nth-child(n + 3) {
			border-top: 1px solid var(--border);
		}
		.charts {
			grid-template-columns: 1fr;
		}
	}
	@media (max-width: 600px) {
		.hide-sm {
			display: none;
		}
		.stat {
			padding: var(--sp-4);
		}
		.value {
			font-size: 18px;
			line-height: 24px;
		}
		.block {
			padding: var(--sp-4);
		}
		.table-wrap {
			margin: 0 calc(-1 * var(--sp-4));
		}
		.versions th:first-child,
		.versions td:first-child {
			padding-left: var(--sp-4);
		}
		.versions th:last-child,
		.versions td:last-child {
			padding-right: var(--sp-4);
		}
	}
</style>
