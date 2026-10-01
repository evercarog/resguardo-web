<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/state';
	import { ArrowLeft, CalendarDays, CircleAlert, CirclePause, CloudOff, LoaderCircle, Monitor, X } from '@lucide/svelte';
	import ActivityChart from '$lib/components/ActivityChart.svelte';
	import MaintenancePanel from '$lib/components/MaintenancePanel.svelte';
	import PlansPanel from '$lib/components/PlansPanel.svelte';
	import RelTime from '$lib/components/RelTime.svelte';
	import StatusChip from '$lib/components/StatusChip.svelte';
	import TaskProgress from '$lib/components/TaskProgress.svelte';
	import { db, friendlyError, loadAll } from '$lib/data.svelte';
	import { formatBytes, formatDate, formatDay, formatDuration, formatNumber, formatTime } from '$lib/format';
	import { HOLD_ADVICE, chipLevel, holdSummary, kindLabel, pauseUntilLabel, repoScheduleLabel, repoStatus, runningSince, taskRunning } from '$lib/status';
	import { supabase } from '$lib/supabase';
	import type { SnapshotRow } from '$lib/types';

	const deviceId = $derived(page.params.device ?? '');
	const repoId = $derived(page.params.repo ?? '');

	let snapshots = $state<SnapshotRow[]>([]);
	/** Días (AAAA-MM-DD) con copias correctas sin cambios («Solo guardar si hay cambios»). */
	let unchangedDays = $state(new Set<string>());
	let loading = $state(true);
	let error = $state('');
	let day = $state<string | null>(null);
	/** Reloj para que el estado ("Al día", "Con retraso"…) se actualice solo. */
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
		// Copias sin cambios de los últimos 60 días (no crean versión). Si falla, se pintan como días sin copias.
		const since = new Date(Date.now() - 61 * 86_400_000).toISOString();
		const { data: runs } = await supabase
			.from('runs')
			.select('started_at, finished_at')
			.eq('device_id', deviceId)
			.eq('repo_id', repoId)
			.eq('unchanged', true)
			.in('result', ['ok', 'warning'])
			.gte('started_at', since)
			.limit(2000);
		unchangedDays = new Set((runs ?? []).map((x) => keyOf(x.finished_at ?? x.started_at)));
	}

	const pad = (n: number) => String(n).padStart(2, '0');
	const keyOf = (iso: string) => {
		const d = new Date(iso);
		return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
	};

	const withDuration = $derived(snapshots.filter((s) => s.duration_s != null));
	const avgDuration = $derived(withDuration.length ? withDuration.reduce((n, s) => n + (s.duration_s ?? 0), 0) / withDuration.length : null);
	const avgAdded = $derived(snapshots.length ? snapshots.reduce((n, s) => n + (s.data_added ?? 0), 0) / snapshots.length : null);

	/** Últimos 60 días: número de copias por día (de hoy hacia atrás). */
	const days = $derived.by(() => {
		const counts = new Map<string, number>();
		for (const s of snapshots) counts.set(keyOf(s.time), (counts.get(keyOf(s.time)) ?? 0) + 1);
		const today = new Date();
		return Array.from({ length: 60 }, (_, i) => {
			const d = new Date(today.getFullYear(), today.getMonth(), today.getDate() - (59 - i));
			const k = `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
			return { key: k, date: d, n: counts.get(k) ?? 0, same: unchangedDays.has(k) };
		});
	});
	const maxDay = $derived(Math.max(1, ...days.map((d) => d.n)));

	const shown = $derived(day ? snapshots.filter((s) => keyOf(s.time) === day) : snapshots);
	const groups = $derived.by(() => {
		const out: { day: string; items: SnapshotRow[] }[] = [];
		for (const s of shown.slice(0, 200)) {
			const label = formatDay(s.time);
			if (out.at(-1)?.day === label) out.at(-1)!.items.push(s);
			else out.push({ day: label, items: [s] });
		}
		return out;
	});
	const dayLabel = (d: Date) => new Intl.DateTimeFormat('es', { weekday: 'short', day: 'numeric', month: 'short' }).format(d);
</script>

<svelte:head><title>{repo?.name ?? 'Destino'} · Resguardo</title></svelte:head>

<div class="page">
	<a class="back btn btn-ghost btn-sm" href="/"><ArrowLeft size={15} /> Estado</a>

	{#if !db.loaded && db.error}
		<div class="notice notice-danger"><CircleAlert size={16} /><p>{db.error}</p></div>
	{:else if !db.loaded}
		<!-- Esqueleto mientras llegan los datos -->
		<div class="skel-head" aria-hidden="true">
			<span class="skel sk-title"></span>
			<span class="skel sk-sub"></span>
		</div>
		<div class="stats" aria-hidden="true">
			{#each { length: 4 } as _}
				<div class="stat skel-stat"><span class="skel sk-label"></span><span class="skel sk-value"></span></div>
			{/each}
		</div>
		<div class="card block" aria-hidden="true"><span class="skel sk-block"></span></div>
		<span class="sr-only" role="status">Cargando…</span>
	{:else if !repo}
		<div class="notice notice-danger"><CircleAlert size={16} /><p>Este destino ya no existe o el equipo aún no lo ha informado. <a href="/">Volver al estado</a>.</p></div>
	{:else}
		<header class="head">
			<div>
				<h1>{repo.name}</h1>
				<p class="faint">
					<span class="devname"><Monitor size={13} aria-hidden="true" />{device?.name ?? 'Equipo'}</span> · {kindLabel(repo.kind)}{repo.host ? ` · ${repo.host}` : ''} · {repoScheduleLabel(repo)}
				</p>
			</div>
			{#if status}<StatusChip level={chipLevel(repo, status.level)} size="md" />{/if}
		</header>

		{#if repo.offsite_hold}
			<div class="notice notice-danger hold" role="alert">
				<CloudOff size={18} />
				<div>
					<p>
						<strong>Cambio inusual: la subida a la nube está frenada.</strong>
						{holdSummary(repo.offsite_hold, now)}
					</p>
					<p class="advice">{HOLD_ADVICE}</p>
				</div>
			</div>
		{/if}

		{#if status?.pause.active}
			<div class="notice paused" role="status">
				<CirclePause size={16} />
				<p>
					<strong>Copias automáticas en pausa</strong>
					{pauseUntilLabel(status.pause.until)}{#if status.pause.since}<span class="faint"> · desde el {formatDate(status.pause.since)}</span>{/if}.
					Mientras tanto no se avisa de retrasos. Puedes reanudarlas desde Resguardo, en el equipo.
				</p>
			</div>
		{/if}

		{#if running}
			<div class="notice notice-info running" role="status">
				<LoaderCircle size={16} />
				<p>
					<strong>Copia automática en curso</strong> desde las {formatTime(running.toISOString())}. El resultado aparecerá aquí
					en cuanto termine.
				</p>
			</div>
		{/if}

		{#if taskRunning(repo, now)}
			<div class="card taskbox"><TaskProgress {repo} {device} {now} /></div>
		{/if}

		<div class="stats">
			<div class="stat">
				<span class="label">Última versión</span>
				<strong>{#if status?.last}<RelTime iso={status.last} {now} capitalize />{:else}—{/if}</strong>
				{#if status?.last}<span class="sub">{formatDate(status.last)}</span>{/if}
				{#if status?.unchangedAt}
					<span class="sub">Última revisión <RelTime iso={status.unchangedAt} {now} /> · sin cambios</span>
				{/if}
			</div>
			<div class="stat">
				<span class="label">Versiones</span>
				<strong>{repo.snapshots_count != null ? formatNumber(repo.snapshots_count) : '—'}</strong>
				<span class="sub">guardadas en este destino</span>
			</div>
			<div class="stat">
				<span class="label">Tamaño protegido</span>
				<strong>{formatBytes(repo.last_total_bytes)}</strong>
				<span class="sub">en la última versión</span>
			</div>
			<div class="stat">
				<span class="label">Duración media</span>
				<strong>{avgDuration != null ? formatDuration(avgDuration) : '—'}</strong>
				<span class="sub">{avgAdded != null ? `+${formatBytes(avgAdded)} por versión` : ''}</span>
			</div>
		</div>

		{#if repo.plans?.length}<PlansPanel plans={repo.plans} {now} />{/if}

		<MaintenancePanel {repo} {now} />

		{#if error}<div class="notice notice-danger"><CircleAlert size={16} /><p>{error}</p></div>{/if}

		{#if loading}
			<div class="card block" aria-hidden="true"><span class="skel sk-block"></span></div>
		{:else if snapshots.length === 0 && !error}
			<div class="card empty">
				<p class="muted">La lista de versiones llegará con el próximo informe del equipo (como mucho en una hora).</p>
			</div>
		{/if}

		{#if snapshots.length}
			<section class="card block">
				<h2>Actividad</h2>
				<div class="charts">
					<ActivityChart title="Datos nuevos por versión" items={snapshots} value={(s) => s.data_added} format={(v) => formatBytes(v)} />
					<ActivityChart title="Duración por versión" items={snapshots} value={(s) => s.duration_s} format={(v) => formatDuration(v)} />
				</div>
			</section>

			<section class="card block">
				<div class="list-head">
					<h2>Versiones</h2>
					{#if day}
						<button class="chip" onclick={() => (day = null)}>
							<CalendarDays size={13} />
							{dayLabel(new Date(`${day}T12:00:00`))}
							<X size={12} />
						</button>
					{:else}
						<span class="faint">{formatNumber(snapshots.length)} {snapshots.length === 1 ? 'más reciente' : 'más recientes'}</span>
					{/if}
				</div>

				<div class="days" aria-label="Versiones de los últimos 60 días">
					{#each days as d (d.key)}
						<button
							class="d"
							class:has={d.n > 0}
							class:same={!d.n && d.same}
							class:on={day === d.key}
							style:--o={d.n ? 0.35 + 0.65 * (d.n / maxDay) : 1}
							title="{dayLabel(d.date)}: {d.n ? `${d.n} ${d.n === 1 ? 'versión' : 'versiones'}` : d.same ? 'sin cambios' : 'sin versiones'}"
							onclick={() => (day = day === d.key ? null : d.key)}
							disabled={!d.n}
						></button>
					{/each}
				</div>
				<p class="faint small">
					Últimos 60 días · toca un día para ver sus versiones.{#if unchangedDays.size}
						{' '}Con borde: se revisó y no había cambios.{/if}
				</p>

				{#each groups as g (g.day)}
					<div class="day">{g.day}</div>
					{#each g.items as s (s.snapshot_id)}
						<div class="row">
							<span class="time">
								{formatTime(s.time)}
								{#if s.duration_s != null}<small>{formatDuration(s.duration_s)}</small>{/if}
							</span>
							<span class="id mono" title="Versión {s.snapshot_id}">{s.snapshot_id.slice(0, 8)}</span>
							<span class="changes faint">
								{#if s.files_new != null}{formatNumber(s.files_new)} nuevos · {formatNumber(s.files_changed ?? 0)} modif.{/if}
							</span>
							<span class="tags" class:none={!s.tags?.length}>{#each s.tags ?? [] as t}<span class="tag">{t}</span>{/each}</span>
							<span class="size">
								{formatBytes(s.total_bytes)}
								{#if s.data_added != null}<small>+{formatBytes(s.data_added)}</small>{/if}
							</span>
						</div>
					{/each}
				{/each}
				{#if shown.length > 200}<p class="faint small">Se muestran las 200 más recientes.</p>{/if}
			</section>
		{/if}
	{/if}
</div>

<style>
	.page {
		display: flex;
		flex-direction: column;
		gap: 16px;
	}
	.back {
		align-self: flex-start;
		margin-left: -8px;
	}
	.head {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		gap: 12px;
	}
	h1 {
		font-size: 24px;
		font-weight: 700;
	}
	.head p {
		margin: 3px 0 0;
		font-size: 13px;
	}
	.devname {
		display: inline-flex;
		align-items: center;
		gap: 5px;
	}
	.hold {
		border: 1px solid color-mix(in srgb, var(--danger) 45%, transparent);
	}
	.hold > div {
		display: flex;
		flex-direction: column;
		gap: 6px;
	}
	.hold .advice {
		font-size: 12.5px;
		color: var(--text-2);
	}
	.taskbox {
		padding: 12px 14px;
	}
	.paused {
		background: var(--surface-3);
		color: var(--text-2);
	}
	.stats {
		display: grid;
		grid-template-columns: repeat(4, minmax(0, 1fr));
		gap: 10px;
	}
	.stat {
		display: flex;
		flex-direction: column;
		gap: 1px;
		padding: 12px 14px;
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--radius-lg);
		box-shadow: var(--shadow-sm);
		animation: rise 0.3s cubic-bezier(0.2, 0.8, 0.2, 1) both;
	}
	.label {
		font-size: 12px;
		font-weight: 600;
		color: var(--text-3);
	}
	.stat strong {
		font-family: var(--font-display);
		font-size: 19px;
	}
	.stat strong::first-letter {
		text-transform: uppercase;
	}
	.sub {
		font-size: 12px;
		color: var(--text-3);
	}
	.block {
		padding: 16px 18px;
		display: flex;
		flex-direction: column;
		gap: 12px;
	}
	h2 {
		font-size: 16px;
		font-weight: 650;
	}
	.charts {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: 24px;
	}
	.empty {
		padding: 20px;
		text-align: center;
	}
	.empty p {
		margin: 0;
	}
	.list-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
	}
	.list-head .faint {
		font-size: 13px;
	}
	.chip {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		height: 28px;
		padding: 0 10px;
		font: inherit;
		font-size: 12.5px;
		font-weight: 600;
		color: var(--accent-soft-text);
		background: var(--accent-soft);
		border: none;
		border-radius: 999px;
		cursor: pointer;
	}
	.days {
		display: grid;
		grid-template-columns: repeat(30, 1fr);
		gap: 3px;
	}
	.d {
		aspect-ratio: 1;
		padding: 0;
		border: none;
		border-radius: 4px;
		background: var(--surface-3);
		cursor: default;
	}
	.d.has {
		background: color-mix(in srgb, var(--accent) calc(var(--o) * 100%), var(--surface-3));
		cursor: pointer;
	}
	/* Día sin versión pero revisado: la copia salió bien sin cambios (neutro). */
	.d.same {
		box-shadow: inset 0 0 0 1.5px color-mix(in srgb, var(--accent) 45%, var(--surface-3));
	}
	.d.on {
		outline: 2px solid var(--text);
		outline-offset: 1px;
	}
	.small {
		margin: -4px 0 0;
		font-size: 12px;
	}
	.day {
		position: sticky;
		/* Justo bajo la barra superior (incluida la muesca del iPhone) */
		top: var(--header-h, 60px);
		padding: 10px 0 4px;
		font-size: 12px;
		font-weight: 650;
		color: var(--text-2);
		background: var(--surface);
		border-bottom: 1px solid var(--border);
	}
	.row {
		display: grid;
		grid-template-columns: 70px 92px minmax(0, 1fr) auto 96px;
		align-items: center;
		gap: 10px;
		padding: 8px 0;
		border-bottom: 1px solid var(--border);
		content-visibility: auto;
		contain-intrinsic-size: auto 44px;
	}
	.time,
	.size {
		display: flex;
		flex-direction: column;
		line-height: 1.25;
		font-variant-numeric: tabular-nums;
	}
	.time {
		font-weight: 600;
	}
	.size {
		align-items: flex-end;
		text-align: right;
		color: var(--text-2);
	}
	.time small,
	.size small {
		font-size: 11.5px;
		font-weight: 400;
		color: var(--text-3);
	}
	.size small {
		color: var(--accent-soft-text);
	}
	.id {
		font-size: 12px;
		color: var(--text-2);
	}
	.changes {
		font-size: 12.5px;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.tags {
		display: flex;
		gap: 4px;
	}
	/* Esqueletos de carga */
	.skel-head {
		display: flex;
		flex-direction: column;
		gap: 8px;
	}
	.sk-title {
		width: 40%;
		height: 26px;
	}
	.sk-sub {
		width: 65%;
		height: 13px;
	}
	.skel-stat {
		gap: 8px;
		animation: none;
	}
	.sk-label {
		width: 55%;
		height: 11px;
	}
	.sk-value {
		width: 40%;
		height: 20px;
	}
	.sk-block {
		height: 120px;
		border-radius: var(--radius);
	}
	.tag {
		padding: 0 8px;
		font-size: 11.5px;
		font-weight: 550;
		line-height: 20px;
		border-radius: 999px;
		background: var(--accent-soft);
		color: var(--accent-soft-text);
	}
	@media (max-width: 720px) {
		h1 {
			font-size: 21px;
		}
		.stats {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
		.charts {
			grid-template-columns: 1fr;
		}
		.days {
			grid-template-columns: repeat(15, 1fr);
		}
		.row {
			grid-template-columns: 64px minmax(0, 1fr) 88px;
			row-gap: 4px;
		}
		.changes {
			display: none;
		}
		/* En móvil, las etiquetas (qué plan hizo la copia) van bajo el identificador */
		.tags {
			grid-column: 2;
			grid-row: 2;
			flex-wrap: wrap;
		}
		.tags.none {
			display: none;
		}
	}
	.running :global(svg) {
		animation: spin 1s linear infinite;
	}
	@keyframes spin {
		to {
			transform: rotate(360deg);
		}
	}
	@media (prefers-reduced-motion: reduce) {
		.running :global(svg) {
			animation: none;
		}
	}
</style>
