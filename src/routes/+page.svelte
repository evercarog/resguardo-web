<script lang="ts">
	import { onMount } from 'svelte';
	import {
		CircleAlert,
		CircleCheck,
		CircleDashed,
		Clock,
		Monitor,
		MoreHorizontal,
		Plus,
		RefreshCw,
		TriangleAlert,
		Wifi,
		WifiOff,
		XCircle
	} from '@lucide/svelte';
	import { db, loadAll, subscribe } from '$lib/data.svelte';
	import { formatBytes, formatDate, formatDuration, formatRelative } from '$lib/format';
	import { LEVEL_ORDER, deviceOnline, elapsedLabel, kindLabel, repoStatus, scheduleLabel, type Level } from '$lib/status';
	import { supabase } from '$lib/supabase';
	import type { Device } from '$lib/types';

	let refreshing = $state(false);
	let now = $state(Date.now());
	let menu = $state<string | null>(null);

	onMount(() => {
		// El tiempo real se conecta cuando la primera carga funcionó (misma sesión válida).
		loadAll().then(() => db.loaded && subscribe());
		const t = setInterval(() => (now = Date.now()), 30_000);
		const onVisible = () => document.visibilityState === 'visible' && loadAll();
		document.addEventListener('visibilitychange', onVisible);
		return () => {
			clearInterval(t);
			document.removeEventListener('visibilitychange', onVisible);
		};
	});

	async function refresh() {
		refreshing = true;
		await loadAll();
		refreshing = false;
	}

	const repoRows = $derived(db.repos.map((r) => ({ repo: r, status: repoStatus(r, now) })));
	const count = (levels: Level[]) => repoRows.filter((r) => levels.includes(r.status.level)).length;
	const offline = $derived(db.devices.filter((d) => !d.revoked_at && !deviceOnline(d, now)).length);
	const attention = $derived(count(['failed', 'overdue', 'late']) + offline);

	/** Equipos agrupados por cliente; lo que necesita atención, primero. */
	const groups = $derived.by(() => {
		const byClient = new Map<string | null, Device[]>();
		for (const d of db.devices) byClient.set(d.client_id, [...(byClient.get(d.client_id) ?? []), d]);
		const worst = (d: Device) =>
			Math.min(5, ...repoRows.filter((r) => r.repo.device_id === d.id).map((r) => LEVEL_ORDER[r.status.level])) -
			(deviceOnline(d, now) ? 0 : 10);
		const out = [...byClient.entries()].map(([clientId, devices]) => ({
			client: db.clients.find((c) => c.id === clientId) ?? null,
			devices: devices.sort((a, b) => worst(a) - worst(b) || a.name.localeCompare(b.name))
		}));
		return out.sort((a, b) => (a.client?.name ?? '~').localeCompare(b.client?.name ?? '~'));
	});

	const ICON = { ok: CircleCheck, late: Clock, overdue: TriangleAlert, failed: XCircle, empty: CircleDashed };

	async function moveDevice(d: Device, clientId: string) {
		menu = null;
		await supabase.from('devices').update({ client_id: clientId || null }).eq('id', d.id);
		await loadAll();
	}

	async function renameDevice(d: Device) {
		menu = null;
		const name = prompt('Nombre del equipo', d.name)?.trim();
		if (!name || name === d.name) return;
		await supabase.from('devices').update({ name }).eq('id', d.id);
		await loadAll();
	}

	async function removeDevice(d: Device) {
		menu = null;
		if (!confirm(`¿Desvincular «${d.name}»? Dejará de enviar su estado. Sus copias no se tocan.`)) return;
		await supabase.from('devices').delete().eq('id', d.id);
		await loadAll();
	}
</script>

<svelte:head><title>Estado · Resguardo</title></svelte:head>

<div class="page">
	<header class="head">
		<div>
			<h1>Estado</h1>
			<p class="faint">
				{#if !db.loaded}Cargando…{:else if attention}{attention}
					{attention === 1 ? 'aviso' : 'avisos'}{:else if db.devices.length}Todo en orden{:else}Aún no hay equipos vinculados{/if}
			</p>
		</div>
		<button class="btn btn-sm" onclick={refresh} disabled={refreshing}>
			<span class:spin={refreshing} style="display:grid"><RefreshCw size={14} /></span> Actualizar
		</button>
	</header>

	{#if db.error}
		<div class="notice notice-danger"><CircleAlert size={16} /><p>{db.error}</p></div>
	{/if}

	{#if db.loaded && db.devices.length}
		<div class="counts">
			<div class="count ok"><CircleCheck size={18} /><strong>{count(['ok'])}</strong><span>Al día</span></div>
			<div class="count late"><Clock size={18} /><strong>{count(['late'])}</strong><span>Con retraso</span></div>
			<div class="count bad"><TriangleAlert size={18} /><strong>{count(['overdue', 'failed'])}</strong><span>Atrasadas o fallidas</span></div>
			<div class="count off"><WifiOff size={18} /><strong>{offline}</strong><span>Equipos sin conexión</span></div>
		</div>

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
								</div>
								<span class="conn" class:online title={d.last_seen_at ? formatDate(d.last_seen_at) : ''}>
									{#if online}<Wifi size={13} /> Conectado{:else}<WifiOff size={13} />
										{d.last_seen_at ? `Sin conexión · ${formatRelative(d.last_seen_at)}` : 'Nunca conectado'}{/if}
								</span>
								<div class="menu-wrap">
									<button class="icon-btn" title="Opciones" onclick={() => (menu = menu === d.id ? null : d.id)}><MoreHorizontal size={16} /></button>
									{#if menu === d.id}
										<div class="menu card">
											<button onclick={() => renameDevice(d)}>Cambiar nombre</button>
											<label>
												Cliente
												<select class="input" value={d.client_id ?? ''} onchange={(e) => moveDevice(d, e.currentTarget.value)}>
													<option value="">Sin cliente</option>
													{#each db.clients as c}<option value={c.id}>{c.name}</option>{/each}
												</select>
											</label>
											<button class="danger" onclick={() => removeDevice(d)}>Desvincular</button>
										</div>
									{/if}
								</div>
							</header>

							{#if repos.length === 0}
								<p class="faint empty">Este equipo aún no tiene copias automáticas programadas.</p>
							{:else}
								<ul class="repos">
									{#each repos as { repo, status } (repo.repo_id)}
										{@const Icon = ICON[status.level]}
										<li class="repo lvl-{status.level}">
											<a class="cover" href="/repo/{repo.device_id}/{encodeURIComponent(repo.repo_id)}" aria-label="Ver {repo.name}"></a>
											<span class="badge lvl-{status.level}"><Icon size={13} />{status.label}</span>
											<div class="repo-main">
												<strong>{repo.name}</strong>
												<span class="faint">{kindLabel(repo.kind)}{repo.host ? ` · ${repo.host}` : ''} · {scheduleLabel(repo.schedule)}</span>
											</div>
											<div class="repo-facts">
												{#if status.last}
													<span title={formatDate(status.last)}>{formatRelative(status.last)}</span>
													<span class="faint">
														{#if repo.last_duration_s != null}{formatDuration(repo.last_duration_s)}{/if}
														{#if repo.last_data_added != null} · +{formatBytes(repo.last_data_added)}{/if}
													</span>
												{:else}
													<span class="faint">sin copias</span>
												{/if}
											</div>
											{#if status.level === 'failed' && repo.last_run?.message}
												<p class="err">{repo.last_run.message}</p>
											{:else if (status.level === 'late' || status.level === 'overdue') && status.since !== null}
												<p class="warnline">{elapsedLabel(status.since - status.expected)} de retraso</p>
											{/if}
										</li>
									{/each}
								</ul>
							{/if}
						</article>
					{/each}
				</div>
			</section>
		{/each}
	{:else if db.loaded}
		<div class="empty-state card">
			<Monitor size={28} />
			<h2>Vincula tu primer equipo</h2>
			<p class="muted">Genera un código aquí y escríbelo en Resguardo, en el equipo que quieras vigilar. Su estado aparecerá en esta página.</p>
			<a class="btn btn-primary" href="/vincular"><Plus size={16} /> Vincular un equipo</a>
		</div>
	{/if}
</div>

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
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(420px, 1fr));
		gap: 12px;
	}
	.device {
		padding: 14px 16px;
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
	.empty {
		margin: 0;
		font-size: 13px;
	}
	.repos {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 6px;
	}
	.repo {
		position: relative;
		transition: border-color 0.15s, background 0.15s;
		display: grid;
		grid-template-columns: auto minmax(0, 1fr) auto;
		align-items: center;
		gap: 10px;
		padding: 9px 11px;
		background: var(--surface-2);
		border: 1px solid var(--border);
		border-left: 3px solid var(--lvl, var(--border));
		border-radius: var(--radius);
	}
	.repo:hover {
		background: var(--surface-3);
	}
	/* Toda la fila es un enlace a la página del repositorio. */
	.cover {
		position: absolute;
		inset: 0;
		border-radius: inherit;
		z-index: 1;
	}
	.lvl-ok {
		--lvl: var(--success);
	}
	.lvl-late {
		--lvl: var(--warn);
	}
	.lvl-overdue,
	.lvl-failed {
		--lvl: var(--danger);
	}
	.badge {
		display: inline-flex;
		align-items: center;
		gap: 4px;
		padding: 0 8px;
		font-size: 11.5px;
		font-weight: 650;
		line-height: 22px;
		white-space: nowrap;
		border-radius: 999px;
		color: var(--lvl, var(--text-2));
		background: color-mix(in srgb, var(--lvl, var(--text-3)) 13%, transparent);
	}
	.repo-main {
		display: flex;
		flex-direction: column;
		min-width: 0;
	}
	.repo-main strong {
		font-size: 13.5px;
	}
	.repo-main .faint {
		font-size: 12px;
		overflow: hidden;
		text-overflow: ellipsis;
		white-space: nowrap;
	}
	.repo-facts {
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		font-size: 12.5px;
		white-space: nowrap;
	}
	.repo-facts .faint {
		font-size: 11.5px;
	}
	.err,
	.warnline {
		grid-column: 1 / -1;
		margin: 0;
		font-size: 12px;
	}
	.err {
		color: var(--danger);
	}
	.warnline {
		color: var(--lvl);
		font-weight: 600;
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
		.conn {
			display: none;
		}
		.repo {
			grid-template-columns: minmax(0, 1fr) auto;
		}
		.badge {
			grid-column: 1 / -1;
			justify-self: start;
		}
	}
</style>
