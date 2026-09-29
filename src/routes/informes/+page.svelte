<script lang="ts">
	import { onMount } from 'svelte';
	import { CircleAlert, CircleCheck, FileText, Printer, TriangleAlert, XCircle } from '@lucide/svelte';
	import Logo from '$lib/components/Logo.svelte';
	import { db, friendlyError, loadAll } from '$lib/data.svelte';
	import { formatBytes, formatDate, formatDuration } from '$lib/format';
	import { kindLabel, repoScheduleLabel, repoStatus } from '$lib/status';
	import { supabase } from '$lib/supabase';
	import type { Device, Repo } from '$lib/types';

	// Informe mensual por cliente: para revisar el mes o entregarlo al cliente
	// (se imprime o se guarda como PDF desde el navegador).

	type SnapRow = { device_id: string; repo_id: string; time: string; data_added: number | null; duration_s: number | null };
	type RunRow = { device_id: string; repo_id: string; started_at: string; result: string; message: string | null };

	const pad = (n: number) => String(n).padStart(2, '0');
	const today = new Date();
	let month = $state(`${today.getFullYear()}-${pad(today.getMonth() + 1)}`);
	/** '' = todos los equipos · 'sin' = sin cliente · id del cliente. */
	let client = $state('');
	let snaps = $state<SnapRow[]>([]);
	let runs = $state<RunRow[]>([]);
	let loading = $state(true);
	let error = $state('');

	const range = $derived.by(() => {
		const [y, m] = month.split('-').map(Number);
		const start = new Date(y, m - 1, 1);
		const end = new Date(y, m, 1);
		return { start, end };
	});
	const monthLabel = $derived(
		new Intl.DateTimeFormat('es', { month: 'long', year: 'numeric' }).format(range.start)
	);

	const devices = $derived<Device[]>(
		db.devices.filter((d) => !d.revoked_at && (client === '' ? true : client === 'sin' ? !d.client_id : d.client_id === client))
	);
	const clientName = $derived(
		client === '' ? 'Todos los equipos' : client === 'sin' ? 'Sin cliente' : (db.clients.find((c) => c.id === client)?.name ?? 'Cliente')
	);

	async function load() {
		loading = true;
		error = '';
		if (!db.loaded) await loadAll();
		const ids = devices.map((d) => d.id);
		if (!ids.length) {
			snaps = [];
			runs = [];
			loading = false;
			return;
		}
		const [s, r] = await Promise.all([
			supabase
				.from('snapshots')
				.select('device_id, repo_id, time, data_added, duration_s')
				.in('device_id', ids)
				.gte('time', range.start.toISOString())
				.lt('time', range.end.toISOString())
				.limit(20000),
			supabase
				.from('runs')
				.select('device_id, repo_id, started_at, result, message')
				.in('device_id', ids)
				.gte('started_at', range.start.toISOString())
				.lt('started_at', range.end.toISOString())
				.limit(20000)
		]);
		if (s.error || r.error) error = friendlyError((s.error ?? r.error)!.message);
		snaps = (s.data ?? []) as SnapRow[];
		runs = (r.data ?? []) as RunRow[];
		loading = false;
	}

	onMount(async () => {
		await loadAll();
		await load();
	});

	/** Días del mes que ya pasaron (el mes en curso cuenta hasta hoy). */
	const daysElapsed = $derived.by(() => {
		const end = range.end.getTime() > Date.now() ? new Date() : new Date(range.end.getTime() - 1);
		return Math.max(1, end.getDate());
	});

	const dayKey = (iso: string) => {
		const d = new Date(iso);
		return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
	};

	/** Resumen de cada destino de cada equipo en el mes. */
	const rows = $derived.by(() =>
		devices.map((d) => ({
			device: d,
			repos: db.repos
				.filter((r) => r.device_id === d.id)
				.map((r: Repo) => {
					const mine = snaps.filter((s) => s.device_id === d.id && s.repo_id === r.repo_id);
					const days = new Set(mine.map((s) => dayKey(s.time))).size;
					const failed = runs.filter((x) => x.device_id === d.id && x.repo_id === r.repo_id && x.result === 'error');
					const added = mine.reduce((n, s) => n + (s.data_added ?? 0), 0);
					const durations = mine.filter((s) => s.duration_s != null);
					const avg = durations.length ? durations.reduce((n, s) => n + (s.duration_s ?? 0), 0) / durations.length : null;
					const last = mine.map((s) => s.time).sort().at(-1) ?? null;
					return {
						repo: r,
						versions: mine.length,
						days,
						coverage: Math.round((days / daysElapsed) * 100),
						failed: failed.length,
						lastError: failed.map((x) => x.message).filter(Boolean).at(-1) ?? null,
						added,
						avg,
						last,
						status: repoStatus(r)
					};
				})
		}))
	);

	const all = $derived(rows.flatMap((r) => r.repos));
	const totals = $derived({
		devices: rows.length,
		repos: all.length,
		versions: all.reduce((n, r) => n + r.versions, 0),
		failed: all.reduce((n, r) => n + r.failed, 0),
		protected: all.reduce((n, r) => n + (r.repo.last_total_bytes ?? 0), 0),
		coverage: all.length ? Math.round(all.reduce((n, r) => n + r.coverage, 0) / all.length) : 0
	});
	const verdict = $derived(
		totals.failed === 0 && all.every((r) => r.status.level === 'ok' || r.status.level === 'empty')
			? { kind: 'ok', text: 'Todas las copias funcionan con normalidad.' }
			: all.some((r) => r.status.level === 'failed' || r.status.level === 'overdue')
				? { kind: 'bad', text: 'Hay copias que necesitan atención.' }
				: { kind: 'warn', text: 'Hubo incidencias puntuales durante el mes.' }
	);
</script>

<svelte:head><title>Informe {clientName} · {monthLabel} · Resguardo</title></svelte:head>

<div class="page">
	<div class="controls no-print">
		<div>
			<h1>Informes</h1>
			<p class="faint">Resumen mensual de las copias de un cliente, listo para imprimir o guardar en PDF.</p>
		</div>
		<div class="pickers">
			<label>
				<span>Cliente</span>
				<select class="input" bind:value={client} onchange={load}>
					<option value="">Todos los equipos</option>
					{#each db.clients as c (c.id)}<option value={c.id}>{c.name}</option>{/each}
					<option value="sin">Sin cliente</option>
				</select>
			</label>
			<label>
				<span>Mes</span>
				<input class="input" type="month" bind:value={month} onchange={load} max={`${today.getFullYear()}-${pad(today.getMonth() + 1)}`} />
			</label>
			<button class="btn btn-primary" onclick={() => window.print()} disabled={loading}><Printer size={15} /> Imprimir o PDF</button>
		</div>
	</div>

	{#if error}<div class="notice notice-danger no-print"><CircleAlert size={16} /><p>{error}</p></div>{/if}

	<article class="report card" aria-busy={loading}>
		<header class="rhead">
			<div class="brand"><Logo size={30} /><strong>Resguardo</strong></div>
			<div class="title">
				<h2>Informe de copias de seguridad</h2>
				<p>{clientName} · <span class="cap">{monthLabel}</span></p>
			</div>
			<p class="faint gen">Generado el {formatDate(new Date().toISOString())}</p>
		</header>

		{#if loading}
			<p class="faint">Preparando el informe…</p>
		{:else if !rows.length}
			<p class="faint empty"><FileText size={16} /> No hay equipos para este cliente.</p>
		{:else}
			<div class="verdict v-{verdict.kind}">
				{#if verdict.kind === 'ok'}<CircleCheck size={18} />{:else if verdict.kind === 'warn'}<TriangleAlert size={18} />{:else}<XCircle size={18} />{/if}
				<strong>{verdict.text}</strong>
			</div>

			<dl class="kpis">
				<div><dt>Equipos</dt><dd>{totals.devices}</dd></div>
				<div><dt>Destinos</dt><dd>{totals.repos}</dd></div>
				<div><dt>Versiones guardadas en el mes</dt><dd>{totals.versions.toLocaleString('es')}</dd></div>
				<div><dt>Días con copia (media)</dt><dd>{totals.coverage} %</dd></div>
				<div><dt>Copias fallidas</dt><dd class:bad={totals.failed > 0}>{totals.failed}</dd></div>
				<div><dt>Datos protegidos</dt><dd>{formatBytes(totals.protected)}</dd></div>
			</dl>

			{#each rows as { device, repos } (device.id)}
				<section class="dev">
					<h3>{device.name}<span class="faint">{device.os ?? ''}</span></h3>
					{#if !repos.length}
						<p class="faint">Sin destinos informados.</p>
					{:else}
						<table>
							<thead>
								<tr>
									<th>Destino</th>
									<th>Programación</th>
									<th class="num">Versiones</th>
									<th class="num">Días con copia</th>
									<th class="num">Fallos</th>
									<th class="num">Datos nuevos</th>
									<th>Última copia</th>
									<th>Estado</th>
								</tr>
							</thead>
							<tbody>
								{#each repos as r (r.repo.repo_id)}
									<tr>
										<td><strong>{r.repo.name}</strong><span class="faint small">{kindLabel(r.repo.kind)}</span></td>
										<td class="small">{repoScheduleLabel(r.repo)}</td>
										<td class="num">{r.versions}</td>
										<td class="num">{r.days}/{daysElapsed} <span class="faint">({r.coverage} %)</span></td>
										<td class="num" class:bad={r.failed > 0}>{r.failed}</td>
										<td class="num">{formatBytes(r.added)}</td>
										<td class="small">{r.last ? formatDate(r.last) : '—'}{#if r.avg != null}<span class="faint"> · {formatDuration(r.avg)}</span>{/if}</td>
										<td><span class="badge lvl-{r.status.level}">{r.status.label}</span></td>
									</tr>
									{#if r.lastError}
										<tr class="errrow"><td colspan="8">Último error: {r.lastError}</td></tr>
									{/if}
								{/each}
							</tbody>
						</table>
					{/if}
				</section>
			{/each}

			<footer class="rfoot faint">
				Datos informados por Resguardo en cada equipo. Las versiones del mes pueden estar incompletas si el destino guarda más de 500
				(se informan las más recientes). Las copias están cifradas con restic; este informe no contiene nombres de archivos.
			</footer>
		{/if}
	</article>
</div>

<style>
	.page {
		display: flex;
		flex-direction: column;
		gap: 18px;
	}
	.controls {
		display: flex;
		justify-content: space-between;
		align-items: flex-end;
		gap: 16px;
		flex-wrap: wrap;
	}
	h1 {
		font-size: 24px;
		font-weight: 700;
	}
	.controls p {
		margin: 4px 0 0;
	}
	.pickers {
		display: flex;
		align-items: flex-end;
		gap: 10px;
		flex-wrap: wrap;
	}
	.pickers label {
		display: flex;
		flex-direction: column;
		gap: 4px;
		font-size: 12px;
		font-weight: 600;
		color: var(--text-2);
	}
	.report {
		display: flex;
		flex-direction: column;
		gap: 18px;
		padding: 26px 28px;
	}
	.rhead {
		display: grid;
		grid-template-columns: auto 1fr auto;
		align-items: center;
		gap: 16px;
		padding-bottom: 14px;
		border-bottom: 1px solid var(--border);
	}
	.brand {
		display: flex;
		align-items: center;
		gap: 8px;
		font-size: 15px;
	}
	.title h2 {
		font-size: 19px;
		font-weight: 700;
	}
	.title p {
		margin: 2px 0 0;
		font-size: 14px;
	}
	.cap {
		text-transform: capitalize;
	}
	.gen {
		font-size: 12px;
		margin: 0;
	}
	.verdict {
		display: flex;
		align-items: center;
		gap: 10px;
		padding: 12px 14px;
		border-radius: 10px;
		font-size: 14px;
	}
	.v-ok {
		color: var(--success);
		background: color-mix(in srgb, var(--success) 10%, transparent);
	}
	.v-warn {
		color: var(--warn);
		background: color-mix(in srgb, var(--warn) 12%, transparent);
	}
	.v-bad {
		color: var(--danger);
		background: color-mix(in srgb, var(--danger) 10%, transparent);
	}
	.kpis {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
		gap: 10px;
		margin: 0;
	}
	.kpis div {
		padding: 10px 12px;
		border: 1px solid var(--border);
		border-radius: 10px;
	}
	.kpis dt {
		font-size: 11.5px;
		color: var(--text-3);
	}
	.kpis dd {
		margin: 2px 0 0;
		font-size: 19px;
		font-weight: 700;
		font-variant-numeric: tabular-nums;
	}
	.bad {
		color: var(--danger);
	}
	.dev h3 {
		display: flex;
		align-items: baseline;
		gap: 8px;
		font-size: 15px;
		margin-bottom: 8px;
	}
	.dev h3 .faint {
		font-size: 12px;
		font-weight: 400;
	}
	table {
		width: 100%;
		border-collapse: collapse;
		font-size: 13px;
	}
	th {
		text-align: left;
		font-size: 11.5px;
		font-weight: 600;
		color: var(--text-3);
		padding: 6px 8px;
		border-bottom: 1px solid var(--border);
	}
	td {
		padding: 8px;
		border-bottom: 1px solid var(--border);
		vertical-align: top;
	}
	td strong {
		display: block;
	}
	.small {
		font-size: 12px;
	}
	.num {
		text-align: right;
		font-variant-numeric: tabular-nums;
		white-space: nowrap;
	}
	.errrow td {
		padding-top: 0;
		color: var(--danger);
		font-size: 12px;
	}
	.badge {
		display: inline-block;
		white-space: nowrap;
		padding: 0 9px;
		font-size: 11.5px;
		font-weight: 650;
		line-height: 22px;
		border-radius: 999px;
		color: var(--lvl, var(--text-2));
		background: color-mix(in srgb, var(--lvl, var(--text-3)) 13%, transparent);
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
	.rfoot {
		font-size: 11.5px;
		line-height: 1.5;
		padding-top: 10px;
		border-top: 1px solid var(--border);
	}
	.empty {
		display: flex;
		align-items: center;
		gap: 8px;
	}
	@media (max-width: 720px) {
		.report {
			padding: 18px 14px;
			overflow-x: auto;
		}
		.rhead {
			grid-template-columns: 1fr;
		}
		table {
			min-width: 640px;
		}
	}
	@media print {
		.no-print {
			display: none !important;
		}
		.report {
			border: none;
			box-shadow: none;
			padding: 0;
		}
		table {
			min-width: 0;
		}
		tr {
			break-inside: avoid;
		}
	}
</style>
