<script lang="ts">
	import { onMount } from 'svelte';
	import { CircleAlert, Monitor, MoreHorizontal, Plus } from '@lucide/svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import PushCard from '$lib/components/PushCard.svelte';
	import RepoCard from '$lib/components/RepoCard.svelte';
	import SummaryHero from '$lib/components/SummaryHero.svelte';
	import { urgentItems } from '$lib/attention';
	import { db, friendlyError, loadAll, subscribe } from '$lib/data.svelte';
	import { dayKey, formatBytes, formatDate, formatDayShort, formatRelative, startOfDay } from '$lib/format';
	import {
		LEVEL_ORDER,
		dayState,
		dayStateLabel,
		deviceOnline,
		lastCheck,
		repoStatus,
		runningSince,
		taskRunning,
		type DayCell,
		type Level
	} from '$lib/status';
	import { supabase } from '$lib/supabase';
	import type { Device } from '$lib/types';

	let refreshing = $state(false);
	let now = $state(Date.now());
	let menu = $state<string | null>(null);
	/** Diálogo abierto: cambiar nombre o desvincular un equipo. */
	let dialog = $state<{ kind: 'rename' | 'remove'; device: Device } | null>(null);

	/** Últimos 14 días por destino ("equipo|destino" → día → marcas), en dos consultas por carga. */
	type DayMarks = { n: number; same: boolean; failed: boolean; warned: boolean };
	let history = $state<Map<string, Map<string, DayMarks>> | null>(null);

	/** El servidor entrega como mucho 1000 filas por consulta: se piden por páginas. */
	async function pages<T>(query: (from: number, to: number) => PromiseLike<{ data: unknown; error: { message: string } | null }>) {
		const out: T[] = [];
		for (let start = 0; start < 20_000; start += 1000) {
			const { data, error: e } = await query(start, start + 999);
			if (e) throw new Error(e.message);
			const rows = (data ?? []) as T[];
			out.push(...rows);
			if (rows.length < 1000) break;
		}
		return out;
	}

	async function loadHistory() {
		// Desde la medianoche (Bogotá) de hace 13 días.
		const from = startOfDay(Date.now(), -13).toISOString();
		try {
			const [snaps, runs] = await Promise.all([
				pages<{ device_id: string; repo_id: string; time: string }>((a, z) =>
					supabase.from('snapshots').select('device_id, repo_id, time').gte('time', from).order('time').range(a, z)
				),
				pages<{ device_id: string; repo_id: string; started_at: string; finished_at: string | null; result: string; unchanged?: boolean }>(
					(a, z) => supabase.from('runs').select('*').gte('started_at', from).order('started_at').range(a, z)
				)
			]);
			const out = new Map<string, Map<string, DayMarks>>();
			const mark = (dev: string, repo: string, iso: string) => {
				const k = `${dev}|${repo}`;
				let m = out.get(k);
				if (!m) out.set(k, (m = new Map()));
				const day = dayKey(new Date(iso));
				let v = m.get(day);
				if (!v) m.set(day, (v = { n: 0, same: false, failed: false, warned: false }));
				return v;
			};
			for (const x of snaps) mark(x.device_id, x.repo_id, x.time).n++;
			for (const x of runs) {
				const v = mark(x.device_id, x.repo_id, x.finished_at ?? x.started_at);
				if (x.result === 'error') v.failed = true;
				else if (x.result === 'warning') v.warned = true;
				else if (x.unchanged) v.same = true;
			}
			history = out;
		} catch {
			// Sin la tira de días si falla: el resto del estado sigue funcionando.
			history = null;
		}
	}

	/** Las 14 casillas (de hace 13 días a hoy) de un destino. */
	function daysOf(deviceId: string, repoId: string): DayCell[] | null {
		if (!history) return null;
		const m = history.get(`${deviceId}|${repoId}`);
		return Array.from({ length: 14 }, (_, i) => {
			const date = startOfDay(now, -(13 - i));
			const key = dayKey(date);
			const v = m?.get(key) ?? { n: 0, same: false, failed: false, warned: false };
			const state = dayState(v);
			return { key, date, state, n: v.n, title: `${formatDayShort(date)}: ${dayStateLabel(state, v.n)}` };
		});
	}

	onMount(() => {
		// El tiempo real se conecta cuando la primera carga funcionó (misma sesión válida).
		loadAll().then(() => {
			if (db.loaded) {
				subscribe();
				loadHistory();
			}
		});
		const t = setInterval(() => (now = Date.now()), 30_000);
		const onVisible = () => {
			if (document.visibilityState === 'visible') loadAll().then(() => (db.loaded ? loadHistory() : undefined));
		};
		document.addEventListener('visibilitychange', onVisible);
		return () => {
			clearInterval(t);
			document.removeEventListener('visibilitychange', onVisible);
		};
	});

	async function refresh() {
		refreshing = true;
		await loadAll();
		if (db.loaded) await loadHistory();
		refreshing = false;
	}

	/**
	 * Orden de gravedad. Una subida frenada por un cambio inusual (posible
	 * ransomware) va antes que todo, también antes que un equipo sin conexión
	 * (que resta 10 al ordenar equipos y clientes).
	 */
	const rank = (r: { repo: { offsite_hold?: unknown }; status: { level: Level } }) => (r.repo.offsite_hold ? -100 : LEVEL_ORDER[r.status.level]);
	const repoRows = $derived(
		db.repos
			.map((r) => ({ repo: r, status: repoStatus(r, now) }))
			// Dentro de cada equipo, lo más grave primero.
			.sort((a, b) => rank(a) - rank(b) || a.repo.name.localeCompare(b.repo.name))
	);
	/** Lo urgente, ordenado (los destinos en pausa no cuentan como atrasados). */
	const urgent = $derived(urgentItems(db.repos, db.devices, db.clients, now));
	const liveDevices = $derived(db.devices.filter((d) => !d.revoked_at));
	const liveRepos = $derived(db.repos.filter((r) => liveDevices.some((d) => d.id === r.device_id)));
	/** «4 equipos · 7 destinos · 2,1 TB protegidos · última copia hace 12 min». */
	const summary = $derived.by(() => {
		const nd = liveDevices.length;
		const nr = liveRepos.length;
		const bytes = liveRepos.reduce((n, r) => n + (r.last_total_bytes ?? 0), 0);
		const last = Math.max(0, ...liveRepos.map((r) => lastCheck(r).at ?? 0));
		const parts = [`${nd} ${nd === 1 ? 'equipo' : 'equipos'}`, `${nr} ${nr === 1 ? 'destino' : 'destinos'}`];
		if (bytes) parts.push(`${formatBytes(bytes)} protegidos`);
		if (last) parts.push(`última copia ${formatRelative(last, now)}`);
		return parts.join(' · ');
	});
	const runningText = $derived.by(() => {
		const n = liveRepos.filter((r) => runningSince(r, now) || taskRunning(r, now)).length;
		return n ? `En marcha ahora en ${n} ${n === 1 ? 'destino' : 'destinos'}` : '';
	});
	const updated = $derived(db.updatedAt ? `Actualizado ${formatRelative(db.updatedAt, now)}` : '');

	/** Equipos agrupados por cliente; lo que necesita atención, primero. */
	const groups = $derived.by(() => {
		const byClient = new Map<string | null, Device[]>();
		for (const d of db.devices) byClient.set(d.client_id, [...(byClient.get(d.client_id) ?? []), d]);
		const worst = (d: Device) =>
			Math.min(6, ...repoRows.filter((r) => r.repo.device_id === d.id).map(rank)) -
			(deviceOnline(d, now) ? 0 : 10);
		const out = [...byClient.entries()].map(([clientId, devices]) => {
			const sorted = devices.sort((a, b) => worst(a) - worst(b) || a.name.localeCompare(b.name));
			return {
				client: db.clients.find((c) => c.id === clientId) ?? null,
				devices: sorted,
				worst: sorted.length ? worst(sorted[0]) : 6
			};
		});
		// Clientes con el equipo en peor estado, primero; a igualdad, por nombre ("Sin cliente" al final).
		return out.sort((a, b) => a.worst - b.worst || (a.client?.name ?? '~').localeCompare(b.client?.name ?? '~'));
	});

	/** Compara versiones "0.5.1" (true si a es anterior a b). */
	function versionLess(a: string, b: string) {
		const pa = a.split('.').map(Number);
		const pb = b.split('.').map(Number);
		for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
			const x = pa[i] ?? 0;
			const y = pb[i] ?? 0;
			if (x !== y) return x < y;
		}
		return false;
	}
	/** La versión más reciente de Resguardo entre los equipos. */
	const newest = $derived(
		db.devices
			.map((d) => d.app_version)
			.filter((v): v is string => !!v && /^\d+(\.\d+)*$/.test(v))
			.reduce<string | null>((max, v) => (!max || versionLess(max, v) ? v : max), null)
	);


	async function moveDevice(d: Device, clientId: string) {
		menu = null;
		await supabase.from('devices').update({ client_id: clientId || null }).eq('id', d.id);
		await loadAll();
	}

	async function renameDevice(d: Device, name: string) {
		if (name === d.name) return;
		const { error } = await supabase.from('devices').update({ name }).eq('id', d.id);
		if (error) throw new Error(friendlyError(error.message));
		await loadAll();
	}

	async function removeDevice(d: Device) {
		const { error } = await supabase.from('devices').delete().eq('id', d.id);
		if (error) throw new Error(friendlyError(error.message));
		await loadAll();
	}

	function openDialog(kind: 'rename' | 'remove', device: Device) {
		menu = null;
		dialog = { kind, device };
	}

	// El menú de opciones se cierra al tocar fuera o con Escape.
	function onWindowClick(e: MouseEvent) {
		if (menu && !(e.target as Element | null)?.closest?.('.menu-wrap')) menu = null;
	}
	function onWindowKey(e: KeyboardEvent) {
		if (menu && e.key === 'Escape') {
			const id = menu;
			menu = null;
			// Devuelve el foco al botón que lo abrió.
			document.querySelector<HTMLElement>(`[aria-controls="menu-${id}"]`)?.focus();
		}
	}
</script>

<svelte:window onclick={onWindowClick} onkeydown={onWindowKey} />

<svelte:head><title>Estado · Resguardo</title></svelte:head>

<div class="page">
	{#if db.error}
		<div class="notice notice-danger" role="alert"><CircleAlert size={16} /><p>{db.error}</p></div>
	{/if}

	{#if db.loaded && db.devices.length}
		<SummaryHero items={urgent} {summary} running={runningText} {updated} {refreshing} onrefresh={refresh} />

		<PushCard placement="top" />

		{#each groups as g (g.client?.id ?? 'none')}
			<section class="group" aria-labelledby="cliente-{g.client?.id ?? 'sin'}">
				<h2 class="overline" id="cliente-{g.client?.id ?? 'sin'}">
					{g.client?.name ?? 'Sin cliente'} <span class="cnt">· {g.devices.length} {g.devices.length === 1 ? 'equipo' : 'equipos'}</span>
				</h2>
				{#each g.devices as d (d.id)}
					{@const online = deviceOnline(d, now)}
					{@const repos = repoRows.filter((r) => r.repo.device_id === d.id)}
					<div class="device" id="equipo-{d.id}">
						<header class="dev-head">
							<div class="dev-name">
								<h3>{d.name}</h3>
								<span class="dev-meta">
									<span class="conn tone-{online ? 'ok' : 'bad'}" title={d.last_seen_at ? formatDate(d.last_seen_at) : ''}>
										<span class="dot" aria-hidden="true"></span>
										{online ? 'Conectado' : d.last_seen_at ? `Sin conexión · ${formatRelative(d.last_seen_at, now)}` : 'Nunca conectado'}
									</span>
									<span class="faint">{d.os ?? ''}{d.app_version ? ` · v${d.app_version}` : ''}</span>
									{#if d.app_version && newest && versionLess(d.app_version, newest)}
										<span class="badge badge-sm tone-warn" title="La versión más reciente en tus equipos es la {newest}">Actualizar a {newest}</span>
									{/if}
								</span>
							</div>
							<div class="menu-wrap">
								<button
									class="icon-btn"
									title="Opciones"
									aria-label="Opciones de {d.name}"
									aria-expanded={menu === d.id}
									aria-controls="menu-{d.id}"
									onclick={() => (menu = menu === d.id ? null : d.id)}><MoreHorizontal size={16} /></button
								>
								{#if menu === d.id}
									<div class="menu" id="menu-{d.id}">
										<button onclick={() => openDialog('rename', d)}>Cambiar nombre</button>
										<label>
											Cliente
											<select class="input" value={d.client_id ?? ''} onchange={(e) => moveDevice(d, e.currentTarget.value)}>
												<option value="">Sin cliente</option>
												{#each db.clients as c}<option value={c.id}>{c.name}</option>{/each}
											</select>
										</label>
										<button class="danger" onclick={() => openDialog('remove', d)}>Desvincular</button>
									</div>
								{/if}
							</div>
						</header>

						{#if repos.length === 0}
							<p class="none">Este equipo aún no tiene copias automáticas programadas.</p>
						{:else}
							<div class="dests">
								{#each repos as { repo, status } (repo.repo_id)}
									<RepoCard {repo} {status} device={d} days={daysOf(d.id, repo.repo_id)} {now} />
								{/each}
							</div>
						{/if}
					</div>
				{/each}
			</section>
		{/each}
	{:else if !db.loaded && !db.error}
		<!-- Esqueleto con la forma del contenido -->
		<div class="skel-hero" aria-hidden="true">
			<span class="skel sk-ic"></span>
			<div class="sk-lines"><span class="skel sk-h"></span><span class="skel sk-s"></span></div>
		</div>
		<div class="dests" aria-hidden="true">
			{#each { length: 2 } as _}
				<div class="card skel-card"><span class="skel sk-t"></span><span class="skel sk-m"></span><span class="skel sk-b"></span></div>
			{/each}
		</div>
		<span class="sr-only" role="status">Cargando…</span>
	{:else if db.loaded}
		<div class="empty-state">
			<Monitor size={32} strokeWidth={1.5} />
			<p>Vincula tu primer equipo para ver aquí el estado de sus copias.</p>
			<a class="btn btn-primary" href="/vincular"><Plus size={16} /> Vincular un equipo</a>
		</div>
	{/if}

	{#if db.loaded}<PushCard placement="bottom" />{/if}
</div>

{#if dialog?.kind === 'rename'}
	{@const d = dialog.device}
	<ConfirmDialog
		title="Cambiar nombre"
		inputLabel="Nombre del equipo"
		value={d.name}
		confirmLabel="Guardar"
		onconfirm={(name) => renameDevice(d, name)}
		onclose={() => (dialog = null)}
	/>
{:else if dialog?.kind === 'remove'}
	{@const d = dialog.device}
	<ConfirmDialog
		title="¿Desvincular «{d.name}»?"
		message="Dejará de enviar su estado. Sus versiones guardadas no se tocan."
		confirmLabel="Desvincular"
		danger
		onconfirm={() => removeDevice(d)}
		onclose={() => (dialog = null)}
	/>
{/if}

<style>
	.page {
		display: flex;
		flex-direction: column;
		gap: var(--sp-8);
	}
	.group {
		display: flex;
		flex-direction: column;
		gap: var(--sp-6);
	}
	.group h2 {
		margin-bottom: calc(-1 * var(--sp-2));
	}
	.cnt {
		font-weight: 500;
		letter-spacing: 0.02em;
		text-transform: none;
	}
	.device {
		display: flex;
		flex-direction: column;
		gap: var(--sp-3);
		scroll-margin-top: calc(var(--header-h) + 16px);
	}
	.dev-head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: var(--sp-3);
	}
	.dev-name {
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
	}
	h3 {
		font-size: var(--fs-h2);
		line-height: var(--lh-h2);
		font-weight: 600;
		letter-spacing: -0.01em;
		overflow-wrap: anywhere;
	}
	.dev-meta {
		display: flex;
		flex-wrap: wrap;
		align-items: center;
		gap: 4px var(--sp-3);
		font-size: var(--fs-sm);
		line-height: var(--lh-sm);
	}
	.conn {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		color: var(--text-2);
	}
	.dests {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--sp-4);
		align-items: stretch;
	}
	.none {
		font-size: var(--fs-sm);
		color: var(--text-3);
	}
	.menu-wrap {
		position: relative;
	}
	.menu {
		position: absolute;
		top: 36px;
		right: 0;
		z-index: 4;
		display: flex;
		flex-direction: column;
		gap: 2px;
		width: 220px;
		padding: 6px;
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--radius-lg);
		box-shadow: var(--shadow-md);
	}
	.menu button {
		padding: 8px 10px;
		font: inherit;
		text-align: left;
		color: var(--text-1);
		background: none;
		border: none;
		border-radius: var(--radius-sm);
		cursor: pointer;
	}
	.menu button:hover {
		background: var(--surface-2);
	}
	.menu .danger {
		color: var(--bad);
	}
	.menu label {
		display: flex;
		flex-direction: column;
		gap: 4px;
		padding: 4px 10px 8px;
		font-size: var(--fs-xs);
		font-weight: 500;
		color: var(--text-3);
	}
	@media (pointer: coarse) {
		.menu {
			top: 46px;
		}
		.menu button {
			min-height: 44px;
		}
	}
	/* Esqueletos */
	.skel-hero {
		display: flex;
		gap: var(--sp-4);
		padding: var(--sp-8);
		border: 1px solid var(--border);
		border-radius: var(--radius-xl);
	}
	.sk-ic {
		flex: none;
		width: 44px;
		height: 44px;
		border-radius: 999px;
	}
	.sk-lines {
		display: flex;
		flex: 1;
		flex-direction: column;
		gap: 10px;
	}
	.sk-h {
		width: 40%;
		height: 30px;
	}
	.sk-s {
		width: 60%;
		height: 14px;
	}
	.skel-card {
		display: flex;
		flex-direction: column;
		gap: 12px;
		padding: var(--sp-5);
	}
	.sk-t {
		width: 45%;
		height: 18px;
	}
	.sk-m {
		width: 70%;
		height: 12px;
	}
	.sk-b {
		height: 56px;
	}
	@media (max-width: 860px) {
		.dests {
			grid-template-columns: minmax(0, 1fr);
		}
	}
	@media (max-width: 720px) {
		.page {
			gap: var(--sp-6);
		}
		.skel-hero {
			padding: var(--sp-5);
		}
	}
</style>
