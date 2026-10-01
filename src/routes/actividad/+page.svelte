<script lang="ts">
	import { onMount, untrack } from 'svelte';
	import {
		ArchiveRestore,
		CircleAlert,
		CircleCheck,
		CloudCheck,
		CloudUpload,
		History,
		Inbox,
		RefreshCw,
		Save,
		ShieldCheck,
		TriangleAlert
	} from '@lucide/svelte';
	import { db, friendlyError, loadAll } from '$lib/data.svelte';
	import { formatBytes, formatDate, formatDay, formatDuration, formatTime, startOfDay } from '$lib/format';
	import { supabase } from '$lib/supabase';
	import type { Device, Repo } from '$lib/types';

	// Actividad: lo que pasó en las copias (automáticas, versiones de otras
	// herramientas, verificaciones y copias externas), agrupado por día.

	type RunRow = {
		device_id: string;
		repo_id: string;
		started_at: string;
		finished_at: string | null;
		result: 'ok' | 'warning' | 'error';
		message: string | null;
		data_added: number | null;
		/** Salió bien sin cambios (no creó versión). */
		unchanged?: boolean;
	};
	type SnapRow = { device_id: string; repo_id: string; snapshot_id: string; time: string; duration_s: number | null; data_added: number | null };
	type Result = 'ok' | 'warning' | 'error';
	type Kind = 'run' | 'snapshot' | 'verify' | 'offsite' | 'verify_offsite' | 'restore_test';

	/** Una entrada de la línea de tiempo. */
	interface Entry {
		key: string;
		kind: Kind;
		time: string;
		result: Result;
		device_id: string;
		repo_id: string;
		message: string | null;
		duration: number | null;
		added: number | null;
		/** Copia correcta sin cambios. */
		unchanged?: boolean;
	}

	type Period = 'today' | '7d' | '30d';
	const PERIODS: { id: Period; label: string }[] = [
		{ id: 'today', label: 'Hoy' },
		{ id: '7d', label: '7 días' },
		{ id: '30d', label: '30 días' }
	];

	let period = $state<Period>('7d');
	/** '' = todos · 'sin' = sin cliente · id del cliente. */
	let client = $state('');
	/** '' = todos los equipos del cliente elegido. */
	let device = $state('');
	let onlyProblems = $state(false);

	let runs = $state<RunRow[]>([]);
	let snaps = $state<SnapRow[]>([]);
	let loading = $state(true);
	let error = $state('');
	/** Cuántas entradas se pintan (con muchos equipos, 30 días pueden ser miles). */
	let limit = $state(150);

	/** Inicio del periodo: medianoche (Bogotá) de hoy, de hace 6 días o de hace 29. */
	const since = $derived(startOfDay(Date.now(), period === 'today' ? 0 : period === '7d' ? -6 : -29));

	/** Equipos del cliente elegido (los desvinculados no cuentan, como en Informes). */
	const clientDevices = $derived<Device[]>(
		db.devices
			.filter((d) => !d.revoked_at && (client === '' ? true : client === 'sin' ? !d.client_id : d.client_id === client))
			.sort((a, b) => a.name.localeCompare(b.name))
	);
	const devices = $derived(device ? clientDevices.filter((d) => d.id === device) : clientDevices);
	/** Clave de los equipos pedidos: si no cambia, no se vuelve a consultar. */
	const idsKey = $derived(devices.map((d) => d.id).join(','));

	// Al cambiar de cliente, el equipo elegido puede dejar de pertenecerle.
	$effect(() => {
		if (device && !clientDevices.some((d) => d.id === device)) device = '';
	});

	/** El servidor entrega como mucho 1000 filas por consulta: se piden por páginas. */
	async function pages<T>(query: (from: number, to: number) => PromiseLike<{ data: unknown; error: { message: string } | null }>) {
		const out: T[] = [];
		for (let start = 0; start < 50_000; start += 1000) {
			const { data, error: e } = await query(start, start + 999);
			if (e) throw new Error(e.message);
			const rows = (data ?? []) as T[];
			out.push(...rows);
			if (rows.length < 1000) break;
		}
		return out;
	}

	/** Número de la última consulta: las respuestas de consultas anteriores se descartan. */
	let request = 0;

	async function load() {
		const mine = ++request;
		loading = true;
		error = '';
		limit = 150;
		const ids = idsKey ? idsKey.split(',') : [];
		if (!ids.length) {
			runs = [];
			snaps = [];
			loading = false;
			return;
		}
		const from = since.toISOString();
		try {
			const [r, s] = await Promise.all([
				pages<RunRow>((a, z) =>
					supabase
						.from('runs')
						.select('device_id, repo_id, started_at, finished_at, result, message, data_added, unchanged')
						.in('device_id', ids)
						.gte('started_at', from)
						.order('started_at', { ascending: false })
						.range(a, z)
				),
				pages<SnapRow>((a, z) =>
					supabase
						.from('snapshots')
						.select('device_id, repo_id, snapshot_id, time, duration_s, data_added')
						.in('device_id', ids)
						.gte('time', from)
						.order('time', { ascending: false })
						.range(a, z)
				)
			]);
			if (mine !== request) return;
			runs = r;
			snaps = s;
		} catch (e) {
			if (mine !== request) return;
			error = friendlyError(e instanceof Error ? e.message : String(e));
		}
		loading = false;
	}

	onMount(() => {
		if (!db.loaded) loadAll();
	});

	/** Actualizar: también el estado de los destinos (verificación y copia externa). */
	async function refresh() {
		await loadAll();
		await load();
	}

	// Se consulta al tener los datos generales y cada vez que cambian el periodo o los equipos.
	$effect(() => {
		if (!db.loaded) return;
		void idsKey;
		void since;
		untrack(load);
	});

	const MINUTE = 60_000;
	const ms = (iso: string) => new Date(iso).getTime();

	/** Todas las entradas del periodo y de los equipos elegidos, de la más reciente a la más antigua. */
	const entries = $derived.by(() => {
		const out: Entry[] = [];
		const allowed = new Set(devices.map((d) => d.id));

		// Copias automáticas informadas por el agente de cada equipo.
		const byRepo = new Map<string, { start: number; end: number }[]>();
		for (const r of runs) {
			if (!allowed.has(r.device_id)) continue;
			const start = ms(r.started_at);
			const end = r.finished_at ? ms(r.finished_at) : start;
			const k = `${r.device_id}|${r.repo_id}`;
			const list = byRepo.get(k);
			if (list) list.push({ start, end });
			else byRepo.set(k, [{ start, end }]);
			out.push({
				key: `run|${k}|${r.started_at}`,
				kind: 'run',
				time: r.finished_at ?? r.started_at,
				result: r.result,
				device_id: r.device_id,
				repo_id: r.repo_id,
				message: r.message,
				duration: r.finished_at ? Math.max(0, (end - start) / 1000) : null,
				added: r.unchanged ? null : r.data_added,
				unchanged: r.result !== 'error' && r.unchanged === true
			});
		}

		// Versiones sin copia automática que las explique (a mano u otra herramienta).
		// Una versión entre 2 min antes del inicio y 2 min después del final de una
		// copia del mismo destino es esa misma copia.
		for (const s of snaps) {
			if (!allowed.has(s.device_id)) continue;
			const t = ms(s.time);
			const k = `${s.device_id}|${s.repo_id}`;
			if ((byRepo.get(k) ?? []).some((r) => t >= r.start - 2 * MINUTE && t <= r.end + 2 * MINUTE)) continue;
			out.push({
				key: `snap|${k}|${s.snapshot_id}`,
				kind: 'snapshot',
				time: s.time,
				result: 'ok',
				device_id: s.device_id,
				repo_id: s.repo_id,
				message: null,
				duration: s.duration_s,
				added: s.data_added
			});
		}

		// Última verificación y última subida a la copia externa de cada destino.
		const from = since.getTime();
		for (const repo of db.repos) {
			if (!allowed.has(repo.device_id)) continue;
			for (const [kind, run] of [
				['verify', repo.verify_run],
				['offsite', repo.offsite_run],
				['verify_offsite', repo.offsite_verify_run],
				['restore_test', repo.restore_test_run]
			] as const) {
				if (!run) continue;
				const time = run.finished ?? run.started;
				if (ms(time) < from) continue;
				out.push({
					key: `${kind}|${repo.device_id}|${repo.repo_id}|${time}`,
					kind,
					time,
					result: run.result,
					device_id: repo.device_id,
					repo_id: repo.repo_id,
					message: run.message,
					duration: run.finished ? Math.max(0, (ms(run.finished) - ms(run.started)) / 1000) : null,
					added: null
				});
			}
		}

		return out.sort((a, b) => ms(b.time) - ms(a.time));
	});

	/** Contadores del periodo (sin el filtro de resultado, para ver el conjunto). */
	const totals = $derived({
		all: entries.length,
		ok: entries.filter((e) => e.result === 'ok').length,
		warning: entries.filter((e) => e.result === 'warning').length,
		error: entries.filter((e) => e.result === 'error').length
	});

	const shown = $derived(onlyProblems ? entries.filter((e) => e.result !== 'ok') : entries);

	/** Entradas agrupadas por día (solo las que se pintan). */
	const groups = $derived.by(() => {
		const out: { day: string; items: Entry[] }[] = [];
		for (const e of shown.slice(0, limit)) {
			const label = formatDay(e.time);
			if (out.at(-1)?.day === label) out.at(-1)!.items.push(e);
			else out.push({ day: label, items: [e] });
		}
		return out;
	});

	const repoOf = (e: Entry): Repo | undefined => db.repos.find((r) => r.device_id === e.device_id && r.repo_id === e.repo_id);
	const deviceName = (id: string) => db.devices.find((d) => d.id === id)?.name ?? 'Equipo';

	const TITLE: Record<Kind, string> = {
		run: 'Copia automática',
		snapshot: 'Versión guardada',
		verify: 'Verificación',
		offsite: 'Subida a la nube',
		verify_offsite: 'Verificación de la nube',
		restore_test: 'Prueba de restauración'
	};
	const KIND_ICON = { run: RefreshCw, snapshot: Save, verify: ShieldCheck, offsite: CloudUpload, verify_offsite: CloudCheck, restore_test: ArchiveRestore };
	const RESULT_LABEL: Record<Result, string> = { ok: 'Correcta', warning: 'Con avisos', error: 'Falló' };
	const RESULT_ICON = { ok: CircleCheck, warning: TriangleAlert, error: CircleAlert };
	/** Tono del sistema de diseño de cada resultado. */
	const TONE: Record<Result, string> = { ok: 'ok', warning: 'warn', error: 'bad' };

	const periodLabel = $derived(period === 'today' ? 'hoy' : period === '7d' ? 'en los últimos 7 días' : 'en los últimos 30 días');
</script>

<svelte:head><title>Actividad · Resguardo</title></svelte:head>

<div class="page">
	<header class="page-head">
		<div>
			<h1 class="page-title">Actividad</h1>
			<p class="page-sub">Copias, verificaciones y subidas de tus equipos, día a día.</p>
		</div>
		<div class="page-actions">
			<button class="btn" onclick={refresh} disabled={loading || !db.loaded}>
				<span class:spin={loading && db.loaded} style="display:grid"><RefreshCw size={16} /></span> Actualizar
			</button>
		</div>
	</header>

	<section class="filters" aria-label="Filtros">
		<div class="seg" role="group" aria-label="Periodo">
			{#each PERIODS as p (p.id)}
				<button class:on={period === p.id} aria-pressed={period === p.id} onclick={() => (period = p.id)}>{p.label}</button>
			{/each}
		</div>
		<div class="pickers">
			<label>
				<span>Cliente</span>
				<select class="input" bind:value={client}>
					<option value="">Todos los clientes</option>
					{#each db.clients as c (c.id)}<option value={c.id}>{c.name}</option>{/each}
					<option value="sin">Sin cliente</option>
				</select>
			</label>
			<label>
				<span>Equipo</span>
				<select class="input" bind:value={device}>
					<option value="">Todos los equipos</option>
					{#each clientDevices as d (d.id)}<option value={d.id}>{d.name}</option>{/each}
				</select>
			</label>
			<label>
				<span>Resultado</span>
				<select class="input" bind:value={onlyProblems}>
					<option value={false}>Todos</option>
					<option value={true}>Solo fallos y avisos</option>
				</select>
			</label>
		</div>
	</section>

	{#if error || (db.error && !db.loaded)}
		<div class="notice notice-danger" role="alert">
			<CircleAlert size={16} />
			<p>{error || db.error}</p>
		</div>
	{/if}

	{#if loading && !error && !(db.error && !db.loaded)}
		<!-- Esqueleto mientras llegan los datos -->
		<div class="card counts" aria-hidden="true">
			{#each { length: 4 } as _}
				<div class="count"><span class="skel sk-num"></span><span class="skel sk-txt"></span></div>
			{/each}
		</div>
		<div class="day" aria-hidden="true">
			<span class="skel sk-day"></span>
			<div class="card list">
				{#each { length: 5 } as _}
					<div class="item sk-item"><span class="skel sk-ic"></span><span class="skel sk-line"></span></div>
				{/each}
			</div>
		</div>
		<span class="sr-only" role="status">Cargando…</span>
	{:else if !error && db.loaded}
		<div class="card counts">
			<button class="count" class:on={!onlyProblems} onclick={() => (onlyProblems = false)} aria-pressed={!onlyProblems}>
				<span class="lbl">En total</span><strong class="num">{totals.all.toLocaleString('es')}</strong>
			</button>
			<div class="count tone-ok"><span class="lbl"><CircleCheck size={12} aria-hidden="true" /> Correctas</span><strong class="num">{totals.ok.toLocaleString('es')}</strong></div>
			<button class="count tone-warn" class:on={onlyProblems} onclick={() => (onlyProblems = true)} aria-pressed={onlyProblems}>
				<span class="lbl"><TriangleAlert size={12} aria-hidden="true" /> Con avisos</span><strong class="num">{totals.warning.toLocaleString('es')}</strong>
			</button>
			<button class="count tone-bad" class:on={onlyProblems} onclick={() => (onlyProblems = true)} aria-pressed={onlyProblems}>
				<span class="lbl"><CircleAlert size={12} aria-hidden="true" /> Fallos</span><strong class="num">{totals.error.toLocaleString('es')}</strong>
			</button>
		</div>

		{#if !devices.length}
			<div class="empty-state">
				<Inbox size={32} strokeWidth={1.5} />
				<p>Este cliente aún no tiene equipos vinculados.</p>
				<a class="btn btn-primary" href="/vincular">Vincular un equipo</a>
			</div>
		{:else if !shown.length}
			<div class="empty-state">
				{#if onlyProblems && entries.length}
					<CircleCheck size={32} strokeWidth={1.5} />
					<p>Sin fallos ni avisos: todo lo que pasó {periodLabel} salió bien.</p>
				{:else}
					<History size={32} strokeWidth={1.5} />
					<p>No hay copias ni verificaciones {periodLabel} en estos equipos.</p>
				{/if}
			</div>
		{:else}
			{#each groups as g (g.day)}
				<section class="day">
					<h2 class="overline">{g.day}</h2>
					<ul class="card list">
						{#each g.items as e (e.key)}
							{@const repo = repoOf(e)}
							{@const KindIcon = KIND_ICON[e.kind]}
							{@const ResultIcon = RESULT_ICON[e.result]}
							<li>
								<a class="item tone-{TONE[e.result]}" href="/repo/{e.device_id}/{encodeURIComponent(e.repo_id)}">
									<span class="kind"><KindIcon size={16} /></span>
									<div class="main">
										<div class="line">
											<strong>{TITLE[e.kind]}</strong>
											{#if e.kind === 'snapshot'}
												<span class="faint small">a mano u otra herramienta</span>
											{:else}
												<span class="badge badge-sm tone-{TONE[e.result]}"><ResultIcon size={12} aria-hidden="true" />{e.unchanged ? 'Sin cambios' : RESULT_LABEL[e.result]}</span>
											{/if}
										</div>
										<span class="faint where">{repo?.name ?? e.repo_id} · {deviceName(e.device_id)}</span>
										{#if e.result !== 'ok' && e.message}
											<span class="msg">{e.message}</span>
										{/if}
									</div>
									<div class="facts">
										<span class="num" title={formatDate(e.time)}>{formatTime(e.time)}</span>
										<span class="faint num">
											{#if e.duration != null}{formatDuration(e.duration)}{/if}
											{#if e.added != null}{e.duration != null ? ' · ' : ''}+{formatBytes(e.added)}{/if}
										</span>
									</div>
								</a>
							</li>
						{/each}
					</ul>
				</section>
			{/each}
			{#if shown.length > limit}
				<button class="btn btn-ghost more" onclick={() => (limit += 150)}>
					Mostrar más ({(shown.length - limit).toLocaleString('es')} restantes)
				</button>
			{/if}
			<p class="faint note">
				«Versión guardada» son versiones que no corresponden a ninguna copia automática: hechas a mano o por otra herramienta. De la
				verificación, la subida a la nube, la verificación de la nube y la prueba de restauración se muestra solo el último resultado de cada
				destino.
			</p>
		{/if}
	{/if}
</div>

<style>
	.page {
		display: flex;
		flex-direction: column;
		gap: var(--sp-5);
	}
	.page-head {
		margin-bottom: 0;
	}

	/* ---------- Filtros ---------- */
	.filters {
		display: flex;
		flex-wrap: wrap;
		align-items: flex-end;
		gap: var(--sp-3);
	}
	/* Pestañas segmentadas del periodo. */
	.seg {
		display: inline-flex;
		gap: 2px;
		padding: 3px;
		background: var(--surface-2);
		border-radius: var(--radius);
	}
	.seg button {
		flex: 1;
		height: 28px;
		padding: 0 12px;
		font: inherit;
		font-size: var(--fs-sm);
		font-weight: 500;
		white-space: nowrap;
		color: var(--text-2);
		background: transparent;
		border: none;
		border-radius: var(--radius-sm);
		cursor: pointer;
		-webkit-tap-highlight-color: transparent;
		transition:
			background var(--dur-fast) var(--ease),
			color var(--dur-fast) var(--ease);
	}
	.seg button:hover {
		color: var(--text-1);
	}
	.seg button.on {
		color: var(--text-1);
		background: var(--surface);
		box-shadow: 0 0 0 1px var(--border);
	}
	.pickers {
		display: grid;
		flex: 1;
		grid-template-columns: repeat(3, minmax(150px, 1fr));
		gap: var(--sp-3);
	}
	.pickers label {
		display: flex;
		flex-direction: column;
		gap: 6px;
		min-width: 0;
		font-size: var(--fs-sm);
		font-weight: 500;
		color: var(--text-1);
	}

	/* ---------- Contadores: un panel con separadores ---------- */
	.counts {
		display: grid;
		grid-template-columns: repeat(4, minmax(0, 1fr));
		overflow: hidden;
	}
	.count {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: 2px;
		padding: var(--sp-4) var(--sp-5);
		font: inherit;
		text-align: left;
		color: var(--text-1);
		background: transparent;
		border: none;
	}
	.count + .count {
		border-left: 1px solid var(--border);
	}
	button.count {
		cursor: pointer;
		-webkit-tap-highlight-color: transparent;
		transition: background var(--dur-fast) var(--ease);
	}
	button.count:hover {
		background: var(--surface-2);
	}
	/* Contador que corresponde al filtro activo: subrayado de acento. */
	button.count.on {
		box-shadow: inset 0 -2px 0 var(--accent);
	}
	.lbl {
		display: inline-flex;
		align-items: center;
		gap: 4px;
		font-size: var(--fs-xs);
		line-height: var(--lh-xs);
		font-weight: 500;
		color: var(--tone, var(--text-3));
	}
	.count strong {
		font-size: var(--fs-stat);
		line-height: var(--lh-stat);
		font-weight: 600;
		letter-spacing: -0.02em;
	}

	/* ---------- Línea de tiempo ---------- */
	.day h2 {
		margin-bottom: var(--sp-2);
	}
	.list {
		display: flex;
		flex-direction: column;
		margin: 0;
		padding: 0;
		overflow: hidden;
		list-style: none;
	}
	.list li + li {
		border-top: 1px solid var(--border);
	}
	.item {
		display: grid;
		grid-template-columns: 16px minmax(0, 1fr) auto;
		align-items: start;
		gap: var(--sp-3);
		min-height: 44px;
		padding: 10px var(--sp-4);
		color: var(--text-1);
		text-decoration: none;
		-webkit-tap-highlight-color: transparent;
		transition: background var(--dur-fast) var(--ease);
	}
	a.item:hover {
		background: var(--surface-2);
		text-decoration: none;
	}
	.kind {
		display: grid;
		padding-top: 2px;
		color: var(--text-3);
	}
	.main {
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
	}
	.line {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: var(--sp-2);
	}
	.line strong {
		font-weight: 500;
	}
	.small {
		font-size: var(--fs-xs);
	}
	.where {
		overflow: hidden;
		font-size: var(--fs-sm);
		line-height: var(--lh-sm);
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.msg {
		font-size: var(--fs-sm);
		line-height: var(--lh-sm);
		color: var(--tone);
		overflow-wrap: anywhere;
	}
	.facts {
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		font-size: var(--fs-sm);
		line-height: var(--lh-sm);
		white-space: nowrap;
	}
	.facts .faint {
		font-size: var(--fs-xs);
		line-height: var(--lh-xs);
	}
	.more {
		align-self: center;
	}
	.note {
		font-size: var(--fs-xs);
		line-height: var(--lh-xs);
	}

	/* ---------- Esqueletos ---------- */
	.sk-num {
		width: 36px;
		height: 22px;
	}
	.sk-txt {
		width: 60%;
		height: 11px;
		margin-top: 4px;
	}
	.sk-day {
		width: 90px;
		height: 12px;
		margin-bottom: 10px;
	}
	.sk-item {
		grid-template-columns: 16px 1fr;
		align-items: center;
	}
	.sk-ic {
		width: 16px;
		height: 16px;
		border-radius: 999px;
	}
	.sk-line {
		width: 70%;
		height: 14px;
	}
	@media (pointer: coarse) {
		.seg button {
			height: 38px;
		}
	}
	@media (max-width: 720px) {
		.filters {
			flex-direction: column;
			align-items: stretch;
		}
		.seg {
			display: flex;
		}
		.pickers {
			grid-template-columns: 1fr 1fr;
		}
		/* El resultado ocupa la fila entera: el texto es largo. */
		.pickers label:last-child {
			grid-column: 1 / -1;
		}
		.counts {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
		.count:nth-child(3) {
			border-left: none;
		}
		.count:nth-child(n + 3) {
			border-top: 1px solid var(--border);
		}
		.item {
			padding: 10px var(--sp-3);
		}
	}
</style>
