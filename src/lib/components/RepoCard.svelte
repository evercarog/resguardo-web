<script lang="ts" module>
	/** Un día de la tira de los últimos 14 días. */
	export interface DayMark {
		key: string;
		date: Date;
		/** Versiones creadas ese día. */
		n: number;
		/** Copia correcta sin cambios (sin versión). */
		same: boolean;
		/** Alguna copia falló ese día. */
		failed: boolean;
	}
</script>

<script lang="ts">
	import {
		ArrowRight,
		CalendarClock,
		CircleAlert,
		CircleCheck,
		CircleDashed,
		CirclePause,
		Clock,
		CloudOff,
		CloudUpload,
		HardDrive,
		Hand,
		LoaderCircle,
		ShieldAlert,
		ShieldCheck,
		TriangleAlert,
		XCircle
	} from '@lucide/svelte';
	import TaskProgress from '$lib/components/TaskProgress.svelte';
	import { formatBytes, formatDate, formatDuration, formatNumber, formatRelative, formatTime } from '$lib/format';
	import {
		OFFSITE_PROVIDERS,
		deviceOnline,
		elapsedLabel,
		holdSummary,
		kindLabel,
		nextExpected,
		offsiteScheduleLabel,
		offsiteVerifySummary,
		pauseUntilLabel,
		planScheduleLabel,
		repoScheduleLabel,
		repoStatus,
		runningSince,
		scheduleLabel,
		taskRunning,
		verifyModeLabel
	} from '$lib/status';
	import type { Device, Repo, TaskRun } from '$lib/types';

	// Tarjeta de un destino en Estado: copias locales, nube, verificación y planes.
	let {
		repo,
		status,
		device,
		days,
		now
	}: { repo: Repo; status: ReturnType<typeof repoStatus>; device: Device | null; days: DayMark[] | null; now: number } = $props();

	const ICON = { ok: CircleCheck, late: Clock, overdue: TriangleAlert, failed: XCircle, empty: CircleDashed, paused: CirclePause };
	const Icon = $derived(ICON[status.level]);
	const href = $derived(`/repo/${repo.device_id}/${encodeURIComponent(repo.repo_id)}`);
	const online = $derived(device ? deviceOnline(device, now) : false);
	const running = $derived(runningSince(repo, now));
	const task = $derived(taskRunning(repo, now));
	const next = $derived(status.pause.active ? null : nextExpected(repo, now));
	const off = $derived(repo.maintenance?.offsite ?? null);
	const verify = $derived(repo.maintenance?.verify ?? null);
	const cloudVerify = $derived(offsiteVerifySummary(repo, now));
	const target = $derived(off ? (off.target_name ?? OFFSITE_PROVIDERS[off.provider] ?? 'Otra ubicación') : '');

	/** ¿La nube tiene ya la última versión local? */
	const cloud = $derived.by(() => {
		const up = repo.offsite_run?.finished ? new Date(repo.offsite_run.finished).getTime() : null;
		const local = repo.last_snapshot_at ? new Date(repo.last_snapshot_at).getTime() : null;
		if (up === null) return { ok: false, text: 'todavía no se ha subido nada' };
		if (local === null || up >= local) return { ok: true, text: 'al día con la copia local' };
		return { ok: false, text: `pendiente: ${elapsedLabel((local - up) / 3_600_000)} de diferencia` };
	});

	/** «hoy, 17:00» o «30 sep, 17:00» para la próxima copia. */
	function nextLabel(d: Date) {
		const today = new Date(now);
		const tomorrow = new Date(today.getFullYear(), today.getMonth(), today.getDate() + 1);
		if (d.toDateString() === today.toDateString()) return `hoy a las ${formatTime(d.toISOString())}`;
		if (d.toDateString() === tomorrow.toDateString()) return `mañana a las ${formatTime(d.toISOString())}`;
		return formatDate(d.toISOString());
	}

	const dayFmt = new Intl.DateTimeFormat('es', { weekday: 'short', day: 'numeric', month: 'short' });
	function dayTitle(d: DayMark) {
		const what = d.n
			? `${d.n} ${d.n === 1 ? 'versión' : 'versiones'}`
			: d.failed
				? 'falló'
				: d.same
					? 'sin cambios'
					: 'sin copias';
		return `${dayFmt.format(d.date)}: ${what}`;
	}
	const maxDay = $derived(Math.max(1, ...(days ?? []).map((d) => d.n)));
</script>

{#snippet result(run: TaskRun | null | undefined, empty: string)}
	{#if run}
		<span class="res res-{run.result}" title={run.finished ? formatDate(run.finished) : ''}>
			{#if run.result === 'ok'}<CircleCheck size={13} />{:else if run.result === 'warning'}<TriangleAlert size={13} />{:else}<CircleAlert
					size={13}
				/>{/if}
			{run.result === 'error' ? 'Falló' : run.result === 'warning' ? 'Con avisos' : 'Bien'} · {formatRelative(run.finished ?? run.started, now)}
		</span>
	{:else}
		<span class="faint">{empty}</span>
	{/if}
{/snippet}

<article class="card dest lvl-{status.level}" class:held={!!repo.offsite_hold}>
	<header class="top">
		<div class="title">
			<h3><a {href}>{repo.name}</a></h3>
			<span class="faint sub">
				<span class="dot" class:online title={online ? 'Conectado' : 'Sin conexión'}></span>
				<span class="sr-only">{online ? 'Conectado' : 'Sin conexión'} ·</span>
				{device?.name ?? 'Equipo'} · {kindLabel(repo.kind)}{repo.host ? ` · ${repo.host}` : ''}
			</span>
		</div>
		{#if repo.offsite_hold}
			<span class="badge lvl-failed"><ShieldAlert size={13} />Cambio inusual</span>
		{:else}
			<span class="badge lvl-{status.level}"><Icon size={13} />{status.label}</span>
		{/if}
	</header>

	{#if running}
		<p class="runline"><span class="spin"><LoaderCircle size={13} /></span> Copiando ahora · desde {formatTime(running.toISOString())}</p>
	{/if}
	{#if status.level === 'failed' && repo.last_run?.message}
		<p class="err">{repo.last_run.message}</p>
	{:else if (status.level === 'late' || status.level === 'overdue') && status.since !== null}
		<p class="warnline">{elapsedLabel(status.since - status.expected)} de retraso</p>
	{/if}
	{#if repo.offsite_hold && !off}
		<p class="err hold">
			<CloudOff size={13} />
			<span><strong>Subida frenada:</strong> {holdSummary(repo.offsite_hold, now)} Revísalo en Resguardo.</span>
		</p>
	{/if}
	{#if status.pause.active}
		<p class="pauseline"><CirclePause size={13} /> Copias automáticas en pausa {pauseUntilLabel(status.pause.until)}</p>
	{/if}

	<!-- Copias locales -->
	<section class="sec" aria-label="Copias locales">
		<h4><HardDrive size={14} /> Copia local</h4>
		<div class="facts">
			<div>
				<span class="k">Última versión</span>
				{#if status.last}
					<span class="v" title={formatDate(status.last)}>{formatRelative(status.last, now)}</span>
					<span class="faint small">
						{[repo.last_data_added != null ? `+${formatBytes(repo.last_data_added)}` : null, repo.last_duration_s != null ? formatDuration(repo.last_duration_s) : null]
							.filter(Boolean)
							.join(' · ')}
					</span>
				{:else}
					<span class="v faint">sin copias</span>
				{/if}
			</div>
			<div>
				<span class="k">Próxima</span>
				<span class="v">{status.pause.active ? 'en pausa' : next ? nextLabel(next) : '—'}</span>
				<span class="faint small">{repoScheduleLabel(repo)}</span>
			</div>
			<div>
				<span class="k">Versiones</span>
				<span class="v">{repo.snapshots_count != null ? formatNumber(repo.snapshots_count) : '—'}</span>
				<span class="faint small">{formatBytes(repo.last_total_bytes)} protegidos</span>
			</div>
		</div>
		{#if status.unchangedAt}
			<p class="faint small" title={formatDate(status.unchangedAt)}>
				Última revisión {formatRelative(status.unchangedAt, now)} · sin cambios
			</p>
		{/if}
		{#if days}
			<div class="strip" role="img" aria-label="Últimos 14 días: {days.filter((d) => d.n || d.same).length} con copia">
				{#each days as d (d.key)}
					<span
						class="d"
						class:has={d.n > 0}
						class:same={!d.n && d.same}
						class:bad={!d.n && !d.same && d.failed}
						style:--o={d.n ? 0.35 + 0.65 * (d.n / maxDay) : 1}
						title={dayTitle(d)}
					></span>
				{/each}
			</div>
		{/if}
	</section>

	<!-- Nube (copia externa) -->
	{#if off}
		<section class="sec" aria-label="Copia en la nube">
			<h4><CloudUpload size={14} /> Nube · {target}</h4>
			{#if repo.offsite_hold}
				<p class="err hold">
					<CloudOff size={13} />
					<span><strong>Subida frenada:</strong> {holdSummary(repo.offsite_hold, now)} Revísalo en Resguardo.</span>
				</p>
			{/if}
			{#if task?.kind === 'offsite' || task?.kind === 'verify_offsite'}
				<TaskProgress {repo} {device} {now} />
			{/if}
			<div class="line">
				{@render result(repo.offsite_run, 'todavía ninguna subida')}
				{#if repo.offsite_run?.message}<span class="faint small msg">{repo.offsite_run.message}</span>{/if}
			</div>
			<div class="line small">
				<span class="faint">{off.schedule ? offsiteScheduleLabel(off.schedule) : 'programada'}</span>
				<span class="sync" class:ok={cloud.ok}>{cloud.text}</span>
			</div>
			{#if cloudVerify}
				<p class="small vline v-{cloudVerify.result ?? 'none'}">
					<ShieldCheck size={13} />
					<span>{cloudVerify.text}{#if cloudVerify.rotation}<br /><span class="faint">{cloudVerify.rotation}</span>{/if}</span>
				</p>
				{#if cloudVerify.message}<p class="err">{cloudVerify.message}</p>{/if}
			{/if}
		</section>
	{/if}

	<!-- Verificación -->
	<section class="sec" aria-label="Verificación">
		<h4><ShieldCheck size={14} /> Verificación</h4>
		{#if task?.kind === 'verify'}
			<TaskProgress {repo} {device} {now} />
		{/if}
		{#if verify}
			<div class="line">
				{@render result(repo.verify_run, 'todavía ninguna')}
				<span class="faint small">{verify.schedule ? scheduleLabel(verify.schedule) : 'programada'}</span>
			</div>
			<p class="faint small">{verifyModeLabel(verify, now)}</p>
			{#if repo.verify_run?.result === 'error' && repo.verify_run.message}<p class="err">{repo.verify_run.message}</p>{/if}
		{:else}
			<p class="faint small">Sin verificación programada.</p>
		{/if}
	</section>

	<!-- Copias (planes) -->
	{#if repo.plans?.length}
		<section class="sec" aria-label="Copias">
			<h4><CalendarClock size={14} /> Copias</h4>
			<ul class="plans">
				{#each repo.plans as p (p.id)}
					<li>
						<span class="pname">
							{#if !p.schedule}<Hand size={12} />{/if}
							<strong>{p.name}</strong>
							<span class="faint small">{p.schedule ? planScheduleLabel(p.schedule) : 'Solo a mano'}</span>
						</span>
						<span class="pres">
							{@render result(p.last_run, 'todavía ninguna')}
							{#if p.last_run && p.last_run.result !== 'error' && p.last_run.unchanged}<span class="faint small"> · sin cambios</span>{/if}
						</span>
						{#if p.last_run?.result === 'error' && p.last_run.message}<span class="err small pmsg">{p.last_run.message}</span>{/if}
					</li>
				{/each}
			</ul>
		</section>
	{/if}

	<footer class="foot">
		<a class="more" {href}>Ver detalle <ArrowRight size={14} /></a>
	</footer>
</article>

<style>
	.dest {
		display: flex;
		flex-direction: column;
		gap: 10px;
		min-width: 0;
		padding: 14px 16px 12px;
		border-top: 3px solid var(--lvl, var(--border));
	}
	.dest.held {
		--lvl: var(--danger);
		border-color: color-mix(in srgb, var(--danger) 45%, var(--border));
		border-top-color: var(--danger);
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
	.lvl-paused {
		--lvl: var(--text-3);
	}
	.top {
		display: flex;
		align-items: flex-start;
		justify-content: space-between;
		gap: 10px;
	}
	.title {
		display: flex;
		flex-direction: column;
		min-width: 0;
	}
	h3 {
		font-size: 15.5px;
		font-weight: 650;
		overflow-wrap: anywhere;
	}
	h3 a {
		color: inherit;
		text-decoration: none;
	}
	h3 a:hover {
		text-decoration: underline;
	}
	.sub {
		display: flex;
		align-items: center;
		gap: 6px;
		font-size: 12px;
		overflow-wrap: anywhere;
	}
	.dot {
		flex: none;
		width: 8px;
		height: 8px;
		border-radius: 50%;
		background: var(--text-3);
	}
	.dot.online {
		background: var(--success);
	}
	.badge {
		display: inline-flex;
		flex: none;
		align-items: center;
		gap: 4px;
		padding: 0 9px;
		font-size: 11.5px;
		font-weight: 650;
		line-height: 24px;
		white-space: nowrap;
		border-radius: 999px;
		color: var(--lvl, var(--text-2));
		background: color-mix(in srgb, var(--lvl, var(--text-3)) 13%, transparent);
	}
	.sec {
		display: flex;
		flex-direction: column;
		gap: 6px;
		padding-top: 10px;
		border-top: 1px solid var(--border);
	}
	h4 {
		display: flex;
		align-items: center;
		gap: 6px;
		font-size: 12px;
		font-weight: 650;
		letter-spacing: 0.03em;
		text-transform: uppercase;
		color: var(--text-3);
		overflow-wrap: anywhere;
	}
	.facts {
		display: grid;
		grid-template-columns: repeat(3, minmax(0, 1fr));
		gap: 10px;
	}
	.facts > div {
		display: flex;
		flex-direction: column;
		min-width: 0;
	}
	.k {
		font-size: 11.5px;
		color: var(--text-3);
	}
	.v {
		font-size: 13.5px;
		font-weight: 600;
	}
	.small {
		font-size: 12px;
	}
	p {
		margin: 0;
	}
	.strip {
		display: grid;
		grid-template-columns: repeat(14, minmax(0, 1fr));
		gap: 3px;
		max-width: 320px;
	}
	.d {
		aspect-ratio: 1;
		border-radius: 3px;
		background: var(--surface-3);
	}
	.d.has {
		background: color-mix(in srgb, var(--accent) calc(var(--o) * 100%), var(--surface-3));
	}
	/* Revisado sin cambios: neutro, con borde. */
	.d.same {
		box-shadow: inset 0 0 0 1.5px color-mix(in srgb, var(--accent) 45%, var(--surface-3));
	}
	.d.bad {
		background: color-mix(in srgb, var(--danger) 55%, var(--surface-3));
	}
	.line {
		display: flex;
		flex-wrap: wrap;
		align-items: baseline;
		justify-content: space-between;
		gap: 4px 10px;
		font-size: 12.5px;
	}
	.vline {
		display: flex;
		align-items: flex-start;
		gap: 6px;
		color: var(--text-2);
	}
	.vline :global(svg) {
		flex: none;
		margin-top: 2px;
	}
	.vline.v-error {
		color: var(--danger);
	}
	.vline.v-warning {
		color: var(--warn);
	}
	.msg {
		overflow-wrap: anywhere;
	}
	.sync {
		font-weight: 600;
		color: var(--warn);
	}
	.sync.ok {
		color: var(--success);
	}
	.res {
		display: inline-flex;
		align-items: center;
		gap: 5px;
		font-weight: 600;
		white-space: nowrap;
	}
	.res-ok {
		color: var(--success);
	}
	.res-warning {
		color: var(--warn);
	}
	.res-error {
		color: var(--danger);
	}
	.plans {
		display: flex;
		flex-direction: column;
		margin: 0;
		padding: 0;
		list-style: none;
	}
	.plans li {
		display: grid;
		grid-template-columns: minmax(0, 1fr) auto;
		gap: 2px 10px;
		align-items: baseline;
		padding: 5px 0;
		font-size: 12.5px;
	}
	.plans li + li {
		border-top: 1px dashed var(--border);
	}
	.pname {
		display: flex;
		flex-wrap: wrap;
		align-items: baseline;
		gap: 2px 8px;
		min-width: 0;
	}
	.pname strong {
		font-weight: 600;
	}
	.pmsg {
		grid-column: 1 / -1;
	}
	.err,
	.warnline,
	.pauseline,
	.runline {
		font-size: 12px;
	}
	.err {
		color: var(--danger);
	}
	.err.hold {
		display: flex;
		align-items: flex-start;
		gap: 6px;
	}
	.err.hold :global(svg) {
		flex: none;
		margin-top: 2px;
	}
	.warnline {
		color: var(--lvl);
		font-weight: 600;
	}
	.pauseline {
		display: flex;
		align-items: center;
		gap: 6px;
		color: var(--text-2);
	}
	.runline {
		display: flex;
		align-items: center;
		gap: 6px;
		color: var(--accent);
		font-weight: 600;
	}
	.spin {
		display: grid;
		animation: spin 1s linear infinite;
	}
	@keyframes spin {
		to {
			transform: rotate(360deg);
		}
	}
	@media (prefers-reduced-motion: reduce) {
		.spin {
			animation: none;
		}
	}
	.foot {
		display: flex;
		justify-content: flex-end;
		margin-top: auto;
		padding-top: 4px;
	}
	.more {
		display: inline-flex;
		align-items: center;
		gap: 4px;
		font-size: 12.5px;
		font-weight: 600;
		color: var(--accent);
		text-decoration: none;
	}
	.more:hover {
		text-decoration: underline;
	}
	.sr-only {
		position: absolute;
		width: 1px;
		height: 1px;
		overflow: hidden;
		clip-path: inset(50%);
		white-space: nowrap;
	}
	@media (max-width: 520px) {
		.facts {
			grid-template-columns: repeat(2, minmax(0, 1fr));
		}
		.facts > div:last-child {
			grid-column: 1 / -1;
		}
		.top {
			flex-direction: column;
		}
		.plans li {
			grid-template-columns: minmax(0, 1fr);
		}
	}
</style>
