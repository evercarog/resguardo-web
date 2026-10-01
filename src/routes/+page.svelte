<script lang="ts">
	import { onMount } from 'svelte';
	import {
		CircleAlert,
		CircleCheck,
		CloudOff,
		Clock,
		Monitor,
		MoreHorizontal,
		Plus,
		RefreshCw,
		TriangleAlert,
		Wifi,
		WifiOff
	} from '@lucide/svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import PushCard from '$lib/components/PushCard.svelte';
	import RepoCard, { type DayMark } from '$lib/components/RepoCard.svelte';
	import { db, friendlyError, loadAll, subscribe } from '$lib/data.svelte';
	import { formatDate, formatRelative } from '$lib/format';
	import { HOLD_ADVICE, LEVEL_ORDER, deviceOnline, holdSummary, repoStatus, type Level } from '$lib/status';
	import { supabase } from '$lib/supabase';
	import type { Device } from '$lib/types';

	let refreshing = $state(false);
	let now = $state(Date.now());
	let menu = $state<string | null>(null);
	/** Diálogo abierto: cambiar nombre o desvincular un equipo. */
	let dialog = $state<{ kind: 'rename' | 'remove'; device: Device } | null>(null);

	/** Últimos 14 días por destino ("equipo|destino" → día → marcas), en dos consultas por carga. */
	let history = $state<Map<string, Map<string, { n: number; same: boolean; failed: boolean }>> | null>(null);
	const pad = (n: number) => String(n).padStart(2, '0');
	const dayKey = (d: Date) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;

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
		const t = new Date();
		const from = new Date(t.getFullYear(), t.getMonth(), t.getDate() - 13).toISOString();
		try {
			const [snaps, runs] = await Promise.all([
				pages<{ device_id: string; repo_id: string; time: string }>((a, z) =>
					supabase.from('snapshots').select('device_id, repo_id, time').gte('time', from).order('time').range(a, z)
				),
				pages<{ device_id: string; repo_id: string; started_at: string; finished_at: string | null; result: string; unchanged?: boolean }>(
					(a, z) => supabase.from('runs').select('*').gte('started_at', from).order('started_at').range(a, z)
				)
			]);
			const out = new Map<string, Map<string, { n: number; same: boolean; failed: boolean }>>();
			const mark = (dev: string, repo: string, iso: string) => {
				const k = `${dev}|${repo}`;
				let m = out.get(k);
				if (!m) out.set(k, (m = new Map()));
				const day = dayKey(new Date(iso));
				let v = m.get(day);
				if (!v) m.set(day, (v = { n: 0, same: false, failed: false }));
				return v;
			};
			for (const x of snaps) mark(x.device_id, x.repo_id, x.time).n++;
			for (const x of runs) {
				const v = mark(x.device_id, x.repo_id, x.finished_at ?? x.started_at);
				if (x.result === 'error') v.failed = true;
				else if (x.unchanged) v.same = true;
			}
			history = out;
		} catch {
			// Sin la tira de días si falla: el resto del estado sigue funcionando.
			history = null;
		}
	}

	/** Las 14 casillas (de hace 13 días a hoy) de un destino. */
	function daysOf(deviceId: string, repoId: string): DayMark[] | null {
		if (!history) return null;
		const m = history.get(`${deviceId}|${repoId}`);
		const t = new Date(now);
		return Array.from({ length: 14 }, (_, i) => {
			const date = new Date(t.getFullYear(), t.getMonth(), t.getDate() - (13 - i));
			const key = dayKey(date);
			const v = m?.get(key);
			return { key, date, n: v?.n ?? 0, same: v?.same ?? false, failed: v?.failed ?? false };
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

	const repoRows = $derived(
		db.repos
			.map((r) => ({ repo: r, status: repoStatus(r, now) }))
			// Dentro de cada equipo, lo más grave primero.
			.sort((a, b) => LEVEL_ORDER[a.status.level] - LEVEL_ORDER[b.status.level] || a.repo.name.localeCompare(b.repo.name))
	);
	const count = (levels: Level[]) => repoRows.filter((r) => levels.includes(r.status.level)).length;
	const offline = $derived(db.devices.filter((d) => !d.revoked_at && !deviceOnline(d, now)).length);
	// Los destinos en pausa no cuentan como atrasados.
	/** Subidas a la nube frenadas por un cambio inusual (posible ransomware). */
	const held = $derived(
		db.repos
			.filter((r) => r.offsite_hold && !db.devices.find((d) => d.id === r.device_id)?.revoked_at)
			.map((r) => ({ repo: r, hold: r.offsite_hold!, device: db.devices.find((d) => d.id === r.device_id) ?? null }))
	);
	const attention = $derived(count(['failed', 'overdue', 'late']) + offline + held.length);
	const paused = $derived(count(['paused']));
	const updated = $derived(db.updatedAt ? `actualizado ${formatRelative(db.updatedAt, now)}` : '');

	/** Equipos agrupados por cliente; lo que necesita atención, primero. */
	const groups = $derived.by(() => {
		const byClient = new Map<string | null, Device[]>();
		for (const d of db.devices) byClient.set(d.client_id, [...(byClient.get(d.client_id) ?? []), d]);
		const worst = (d: Device) =>
			Math.min(6, ...repoRows.filter((r) => r.repo.device_id === d.id).map((r) => LEVEL_ORDER[r.status.level])) -
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
	<header class="head">
		<div>
			<h1>Estado</h1>
			<p class="faint">
				{#if !db.loaded}
					{db.error ? '' : 'Cargando…'}
				{:else}
					{#if attention}
						<span class="attn">{attention} {attention === 1 ? 'cosa necesita' : 'cosas necesitan'} tu atención</span>
					{:else if db.devices.length}
						<span class="calm">Todo en orden</span>
					{:else}
						Aún no hay equipos vinculados
					{/if}
					{#if updated}<span title={db.updatedAt ? formatDate(new Date(db.updatedAt).toISOString()) : ''}> · {updated}</span>{/if}
				{/if}
			</p>
		</div>
		<button class="btn btn-sm" onclick={refresh} disabled={refreshing}>
			<span class:spin={refreshing} style="display:grid"><RefreshCw size={14} /></span> Actualizar
		</button>
	</header>

	{#if db.error}
		<div class="notice notice-danger"><CircleAlert size={16} /><p>{db.error}</p></div>
	{/if}

	{#each held as h (`${h.repo.device_id}|${h.repo.repo_id}`)}
		<div class="notice notice-danger hold" role="alert">
			<CloudOff size={18} />
			<div>
				<p>
					<strong>Cambio inusual en «{h.repo.name}»{h.device ? ` (${h.device.name})` : ''}.</strong>
					{holdSummary(h.hold, now)} La subida a la nube está frenada.
				</p>
				<p class="advice">{HOLD_ADVICE}</p>
				<a class="btn btn-sm" href="/repo/{h.repo.device_id}/{encodeURIComponent(h.repo.repo_id)}">Ver el destino</a>
			</div>
		</div>
	{/each}

	{#if db.loaded && db.devices.length}
		<div class="counts">
			<div class="count ok"><CircleCheck size={18} /><strong>{count(['ok'])}</strong><span>Al día{paused ? ` · ${paused} en pausa` : ''}</span></div>
			<div class="count late"><Clock size={18} /><strong>{count(['late'])}</strong><span>Con retraso</span></div>
			<div class="count bad"><TriangleAlert size={18} /><strong>{count(['overdue', 'failed'])}</strong><span>Atrasadas o fallidas</span></div>
			<div class="count off"><WifiOff size={18} /><strong>{offline}</strong><span>Equipos sin conexión</span></div>
		</div>

		<PushCard placement="top" />

		{#each groups as g (g.client?.id ?? 'none')}
			<section class="group">
				<h2>{g.client?.name ?? 'Sin cliente'}</h2>
				<div class="devices">
					{#each g.devices as d, i (d.id)}
						{@const online = deviceOnline(d, now)}
						{@const repos = repoRows.filter((r) => r.repo.device_id === d.id)}
						<article class="card device" style:--i={i}>
							<header class="dev-head">
								<span class="dev-icon"><Monitor size={17} /></span>
								<div class="dev-name">
									<strong>{d.name}</strong>
									<span class="faint">{d.os ?? ''}{d.app_version ? ` · v${d.app_version}` : ''}</span>
									{#if d.app_version && newest && versionLess(d.app_version, newest)}
										<span class="old-version" title="La versión más reciente en tus equipos es la {newest}">Actualizar a {newest}</span>
									{/if}
									<!-- En el celular, la conexión va aquí, bajo el nombre -->
									<span class="conn conn-short" class:online>
										{#if online}<Wifi size={12} /> Conectado{:else}<WifiOff size={12} />
											{d.last_seen_at ? `Sin conexión · ${formatRelative(d.last_seen_at, now)}` : 'Nunca conectado'}{/if}
									</span>
								</div>
								<span class="conn conn-long" class:online title={d.last_seen_at ? formatDate(d.last_seen_at) : ''}>
									{#if online}<Wifi size={13} /> Conectado{:else}<WifiOff size={13} />
										{d.last_seen_at ? `Sin conexión · ${formatRelative(d.last_seen_at, now)}` : 'Nunca conectado'}{/if}
								</span>
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
										<div class="menu card" id="menu-{d.id}">
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
								<p class="faint empty">Este equipo aún no tiene copias automáticas programadas.</p>
							{:else}
								<div class="dests">
									{#each repos as { repo, status } (repo.repo_id)}
										<RepoCard {repo} {status} device={d} days={daysOf(d.id, repo.repo_id)} {now} />
									{/each}
								</div>
							{/if}
						</article>
					{/each}
				</div>
			</section>
		{/each}
	{:else if !db.loaded && !db.error}
		<!-- Esqueleto mientras llega la primera carga -->
		<div class="counts" aria-hidden="true">
			{#each { length: 4 } as _}
				<div class="count skel-count"><span class="skel sk-ic"></span><span class="skel sk-num"></span><span class="skel sk-txt"></span></div>
			{/each}
		</div>
		<div class="devices" aria-hidden="true">
			{#each { length: 2 } as _}
				<div class="card device skel-device">
					<div class="dev-head"><span class="skel sk-dev"></span><span class="skel sk-name"></span></div>
					<span class="skel sk-row"></span>
					<span class="skel sk-row"></span>
				</div>
			{/each}
		</div>
		<span class="sr-only" role="status">Cargando…</span>
	{:else if db.loaded}
		<div class="empty-state card">
			<Monitor size={28} />
			<h2>Vincula tu primer equipo</h2>
			<p class="muted">Genera un código aquí y escríbelo en Resguardo, en el equipo que quieras vigilar. Su estado aparecerá en esta página.</p>
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
		message="Dejará de enviar su estado. Sus copias no se tocan."
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
		gap: 18px;
	}
	.head {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
	}
	h1 {
		font-size: 24px;
		font-weight: 700;
	}
	.head p {
		margin: 2px 0 0;
		font-size: 13.5px;
	}
	.attn {
		color: var(--text-2);
		font-weight: 600;
	}
	.calm {
		color: var(--success);
		font-weight: 600;
	}
	.sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip-path: inset(50%);
		white-space: nowrap;
	}
	/* Esqueletos de carga */
	.skel-count,
	.skel-device {
		animation: none;
	}
	.skel-count {
		row-gap: 6px;
	}
	.sk-ic {
		width: 18px;
		height: 18px;
		border-radius: 50%;
	}
	.sk-num {
		width: 32px;
		height: 20px;
	}
	.sk-txt {
		grid-column: 2;
		width: 70%;
		height: 11px;
	}
	.sk-dev {
		flex: none;
		width: 34px;
		height: 34px;
		border-radius: 9px;
	}
	.sk-name {
		width: 45%;
		height: 16px;
	}
	.sk-row {
		height: 46px;
		border-radius: var(--radius);
	}
	.counts {
		display: grid;
		grid-template-columns: repeat(4, minmax(0, 1fr));
		gap: 10px;
	}
	.count {
		display: grid;
		grid-template-columns: auto 1fr;
		column-gap: 10px;
		align-items: center;
		padding: 12px 14px;
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--radius-lg);
		box-shadow: var(--shadow-sm);
		animation: rise 0.3s cubic-bezier(0.2, 0.8, 0.2, 1) both;
	}
	.count :global(svg) {
		grid-row: span 2;
	}
	.count strong {
		font-family: var(--font-display);
		font-size: 22px;
		line-height: 1.1;
		color: var(--text);
	}
	.count span {
		font-size: 12px;
		color: var(--text-3);
	}
	.count.ok {
		color: var(--success);
	}
	.count.late {
		color: var(--warn);
	}
	.count.bad {
		color: var(--danger);
	}
	.count.off {
		color: var(--text-3);
	}
	.group h2 {
		margin-bottom: 10px;
		font-size: 13px;
		font-weight: 650;
		letter-spacing: 0.05em;
		text-transform: uppercase;
		color: var(--text-3);
	}
	.devices {
		display: flex;
		flex-direction: column;
		gap: 12px;
	}
	/* Destinos del equipo: tarjetas grandes, 2 por fila (1 en pantallas estrechas). */
	.dests {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: 12px;
		align-items: start;
	}
	@media (max-width: 860px) {
		.dests {
			grid-template-columns: minmax(0, 1fr);
		}
	}
	.device {
		padding: 14px 16px;
		background: var(--surface-2);
		display: flex;
		flex-direction: column;
		gap: 10px;
		animation: rise 0.35s cubic-bezier(0.2, 0.8, 0.2, 1) both;
		animation-delay: calc(var(--i) * 40ms);
	}
	.dev-head {
		display: flex;
		align-items: center;
		gap: 10px;
	}
	.dev-icon {
		display: grid;
		place-items: center;
		width: 34px;
		height: 34px;
		flex: none;
		border-radius: 9px;
		color: var(--text-2);
		background: var(--surface-3);
	}
	.dev-name {
		display: flex;
		flex-direction: column;
		min-width: 0;
		flex: 1;
	}
	.dev-name strong {
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.dev-name .faint {
		font-size: 12px;
	}
	.conn {
		display: inline-flex;
		align-items: center;
		gap: 5px;
		flex: none;
		font-size: 12px;
		font-weight: 600;
		color: var(--text-3);
	}
	.conn.online {
		color: var(--success);
	}
	.conn-short {
		display: none;
	}
	.menu-wrap {
		position: relative;
	}
	.menu {
		position: absolute;
		right: 0;
		top: 32px;
		z-index: 4;
		display: flex;
		flex-direction: column;
		gap: 4px;
		width: 210px;
		padding: 6px;
		box-shadow: var(--shadow-md);
	}
	.menu button {
		padding: 8px 10px;
		font: inherit;
		font-size: 13px;
		text-align: left;
		color: var(--text);
		background: none;
		border: none;
		border-radius: var(--radius-sm);
		cursor: pointer;
	}
	.menu button:hover {
		background: var(--surface-3);
	}
	.menu .danger {
		color: var(--danger);
	}
	.menu label {
		display: flex;
		flex-direction: column;
		gap: 4px;
		padding: 4px 10px 8px;
		font-size: 12px;
		color: var(--text-3);
	}
	.menu select {
		height: 30px;
		font-size: 13px;
	}
	@media (pointer: coarse) {
		.menu {
			top: 46px;
		}
		.menu button {
			min-height: 44px;
		}
		.menu select {
			height: 44px;
		}
	}
	.empty {
		margin: 0;
		font-size: 13px;
	}
	.hold {
		border: 1px solid color-mix(in srgb, var(--danger) 45%, transparent);
	}
	.hold > div {
		display: flex;
		flex-direction: column;
		align-items: flex-start;
		gap: 8px;
	}
	.hold .advice {
		font-size: 12.5px;
		color: var(--text-2);
	}
	.empty-state {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 10px;
		padding: 40px 24px;
		text-align: center;
		color: var(--text-3);
	}
	.empty-state h2 {
		color: var(--text);
		font-size: 18px;
	}
	.empty-state p {
		max-width: 420px;
		margin: 0 0 8px;
		line-height: 1.55;
	}
	@media (max-width: 720px) {
		h1 {
			font-size: 22px;
		}
		.counts {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
		.devices {
			grid-template-columns: 1fr;
		}
		.conn-long {
			display: none;
		}
		.conn-short {
			display: inline-flex;
			font-size: 11.5px;
		}
		/* 16px evita el zoom de iOS al tocar el selector de cliente */
		.menu select {
			font-size: 16px;
		}
	}
	.old-version {
		display: inline-block;
		margin-top: 2px;
		padding: 0 7px;
		font-size: 11px;
		font-weight: 600;
		line-height: 18px;
		border-radius: 999px;
		color: var(--warn);
		background: color-mix(in srgb, var(--warn) 12%, transparent);
	}
</style>
