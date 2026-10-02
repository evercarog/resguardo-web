<script lang="ts">
	import { onMount } from 'svelte';
	import {
		ArchiveRestore,
		CircleAlert,
		CircleCheck,
		CirclePause,
		CirclePlay,
		CloudCheck,
		CloudOff,
		CloudUpload,
		History,
		Play,
		RefreshCw,
		ShieldCheck,
		TriangleAlert
	} from '@lucide/svelte';
	import { db } from '$lib/data.svelte';
	import { formatBytes, formatDate, formatDay, formatDuration, formatTime, startOfDay } from '$lib/format';
	import { supabase } from '$lib/supabase';
	import type { DeviceCommand, Repo } from '$lib/types';

	// «Historia» de un repositorio: todo lo que le ha pasado, en una sola línea
	// de tiempo (copias, subidas, verificaciones, pruebas de restauración,
	// copias pedidas a distancia, pausas y cambios inusuales).
	let { repo }: { repo: Repo } = $props();

	type Group = 'copias' | 'mantenimiento' | 'distancia' | 'estado';
	type Tone = 'ok' | 'warn' | 'bad' | 'info' | 'paused' | 'neutral';
	interface Item {
		key: string;
		time: string;
		group: Group;
		tone: Tone;
		icon: typeof History;
		title: string;
		/** Chip con el resultado. */
		chip: string;
		detail: string | null;
		meta: string | null;
	}

	type RunRow = { started_at: string; finished_at: string | null; result: 'ok' | 'warning' | 'error'; message: string | null; data_added: number | null; unchanged?: boolean };
	let runs = $state<RunRow[]>([]);
	let loaded = $state(false);

	onMount(async () => {
		const { data } = await supabase
			.from('runs')
			.select('*')
			.eq('device_id', repo.device_id)
			.eq('repo_id', repo.repo_id)
			.gte('started_at', startOfDay(Date.now(), -90).toISOString())
			.order('started_at', { ascending: false })
			.limit(1000);
		runs = (data ?? []) as RunRow[];
		loaded = true;
	});

	const WORD = { ok: 'Correcta', warning: 'Con avisos', error: 'Falló' } as const;
	const TONE = { ok: 'ok', warning: 'warn', error: 'bad' } as const;
	const ms = (iso: string) => new Date(iso).getTime();

	const items = $derived.by(() => {
		const out: Item[] = [];
		for (const r of runs) {
			const unchanged = r.result !== 'error' && r.unchanged;
			const dur = r.finished_at ? (ms(r.finished_at) - ms(r.started_at)) / 1000 : null;
			out.push({
				key: `run|${r.started_at}`,
				time: r.finished_at ?? r.started_at,
				group: 'copias',
				tone: TONE[r.result],
				icon: RefreshCw,
				title: 'Copia automática',
				chip: unchanged ? 'Sin cambios' : WORD[r.result],
				detail: r.result !== 'ok' ? r.message : null,
				meta: [dur != null ? formatDuration(dur) : null, !unchanged && r.data_added != null ? `+${formatBytes(r.data_added)}` : null].filter(Boolean).join(' · ') || null
			});
		}
		const tasks: [string, typeof History, string, Repo['verify_run'] | undefined][] = [
			['verify', ShieldCheck, 'Verificación', repo.verify_run],
			['offsite', CloudUpload, 'Subida a la nube', repo.offsite_run],
			['vcloud', CloudCheck, 'Verificación de la nube', repo.offsite_verify_run],
			['restore', ArchiveRestore, 'Prueba de restauración', repo.restore_test_run]
		];
		for (const [k, icon, title, run] of tasks) {
			if (!run) continue;
			out.push({
				key: `${k}|${run.started}`,
				time: run.finished ?? run.started,
				group: 'mantenimiento',
				tone: TONE[run.result],
				icon,
				title,
				chip: WORD[run.result],
				detail: run.message || null,
				meta: null
			});
		}
		const REMOTE: Record<DeviceCommand['status'], [Tone, string]> = {
			pending: ['info', 'Pedida'],
			claimed: ['info', 'En marcha'],
			done: ['ok', 'Hecha'],
			failed: ['bad', 'Falló'],
			rejected: ['warn', 'Rechazada'],
			expired: ['warn', 'Caducó']
		};
		for (const c of db.commands.filter((c) => c.device_id === repo.device_id && c.repo_id === repo.repo_id)) {
			const plan = repo.plans?.find((p) => p.id === c.plan_id)?.name ?? c.plan_id;
			const [tone, chip] = REMOTE[c.status];
			out.push({
				key: `cmd|${c.id}`,
				time: c.requested_at,
				group: 'distancia',
				tone,
				icon: Play,
				title: 'Copia pedida a distancia',
				chip,
				detail: c.message,
				meta: `«${plan}» · desde ${c.requested_from === 'web' ? 'la web' : c.requested_from}`
			});
		}
		if (repo.paused && repo.paused_since) {
			out.push({
				key: 'pause',
				time: repo.paused_since,
				group: 'estado',
				tone: 'paused',
				icon: CirclePause,
				title: 'Copias automáticas en pausa',
				chip: 'En pausa',
				detail: repo.paused_until ? `Hasta el ${formatDate(repo.paused_until)}.` : 'Hasta que se reanuden a mano.',
				meta: null
			});
		}
		if (repo.resumed_at) {
			out.push({
				key: 'resume',
				time: repo.resumed_at,
				group: 'estado',
				tone: 'ok',
				icon: CirclePlay,
				title: 'Copias automáticas reanudadas',
				chip: 'Reanudadas',
				detail: null,
				meta: null
			});
		}
		if (repo.offsite_hold) {
			out.push({
				key: 'hold',
				time: repo.offsite_hold.since,
				group: 'estado',
				tone: 'bad',
				icon: CloudOff,
				title: 'Cambio inusual: subida a la nube frenada',
				chip: 'Por revisar',
				detail: 'Una copia cambió mucho más de lo normal. Revísalo en Resguardo, en ese equipo.',
				meta: null
			});
		}
		return out.sort((a, b) => ms(b.time) - ms(a.time));
	});

	const FILTERS: { id: 'todo' | Group | 'problemas'; label: string }[] = [
		{ id: 'todo', label: 'Todo' },
		{ id: 'copias', label: 'Copias' },
		{ id: 'mantenimiento', label: 'Mantenimiento' },
		{ id: 'distancia', label: 'A distancia' },
		{ id: 'problemas', label: 'Problemas' }
	];
	let filter = $state<(typeof FILTERS)[number]['id']>('todo');
	const STEP = 25;
	let limit = $state(STEP);
	const shown = $derived(
		filter === 'todo'
			? items
			: filter === 'problemas'
				? items.filter((i) => i.tone === 'bad' || i.tone === 'warn')
				: items.filter((i) => i.group === filter || (filter === 'mantenimiento' && i.group === 'estado'))
	);
	const groups = $derived.by(() => {
		const out: { day: string; items: Item[] }[] = [];
		for (const i of shown.slice(0, limit)) {
			const d = formatDay(i.time);
			if (out.at(-1)?.day === d) out.at(-1)!.items.push(i);
			else out.push({ day: d, items: [i] });
		}
		return out;
	});
	const ICON = { ok: CircleCheck, warn: TriangleAlert, bad: CircleAlert, info: CircleCheck, paused: CirclePause, neutral: CircleCheck };
</script>

<section class="card hist" aria-labelledby="t-historia">
	<div class="section-head">
		<h2 class="section-title" id="t-historia">Historia <span class="count">· últimos 90 días</span></h2>
		<div class="seg" role="group" aria-label="Qué mostrar">
			{#each FILTERS as f (f.id)}
				<button class:on={filter === f.id} aria-pressed={filter === f.id} onclick={() => ((filter = f.id), (limit = STEP))}>{f.label}</button>
			{/each}
		</div>
	</div>

	{#if !loaded}
		<span class="skel sk" aria-hidden="true"></span>
	{:else if !shown.length}
		<div class="empty-state small-empty">
			<History size={32} strokeWidth={1.5} />
			<p>{filter === 'problemas' ? 'Sin fallos ni avisos en estos 90 días.' : 'Todavía no hay nada que contar aquí.'}</p>
		</div>
	{:else}
		{#each groups as g (g.day)}
			<h3 class="overline day">{g.day}</h3>
			<ul class="list">
				{#each g.items as i (i.key)}
					{@const Icon = i.icon}
					{@const ToneIcon = ICON[i.tone]}
					<li class="row tone-{i.tone}">
						<span class="ic" aria-hidden="true"><Icon size={16} /></span>
						<div class="main">
							<div class="line">
								<strong>{i.title}</strong>
								<span class="badge badge-sm tone-{i.tone}"><ToneIcon size={12} aria-hidden="true" />{i.chip}</span>
							</div>
							{#if i.meta}<span class="faint meta">{i.meta}</span>{/if}
							{#if i.detail}<span class="detail">{i.detail}</span>{/if}
						</div>
						<span class="when num" title={formatDate(i.time)}>{formatTime(i.time)}</span>
					</li>
				{/each}
			</ul>
		{/each}
		{#if shown.length > limit}
			<button class="btn btn-ghost more" onclick={() => (limit += STEP)}>Mostrar más ({shown.length - limit} más)</button>
		{/if}
	{/if}
</section>

<style>
	.hist {
		display: flex;
		flex-direction: column;
		gap: var(--sp-3);
		padding: var(--sp-5);
	}
	.section-head {
		flex-wrap: wrap;
		margin-bottom: 0;
	}
	.seg {
		display: inline-flex;
		flex-wrap: wrap;
		gap: 2px;
		padding: 3px;
		background: var(--surface-2);
		border-radius: var(--radius);
	}
	.seg button {
		height: 26px;
		padding: 0 10px;
		font: inherit;
		font-size: var(--fs-sm);
		font-weight: 500;
		color: var(--text-2);
		background: transparent;
		border: none;
		border-radius: var(--radius-sm);
		cursor: pointer;
	}
	.seg button:hover {
		color: var(--text-1);
	}
	.seg button.on {
		color: var(--text-1);
		background: var(--surface);
		box-shadow: 0 0 0 1px var(--border);
	}
	.day {
		margin-top: var(--sp-2);
	}
	.list {
		margin: 0;
		padding: 0;
		list-style: none;
	}
	.row {
		display: grid;
		grid-template-columns: 16px minmax(0, 1fr) auto;
		align-items: start;
		gap: var(--sp-3);
		min-height: 44px;
		padding: 10px 0;
		border-top: 1px solid var(--border);
	}
	.ic {
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
	.meta,
	.detail {
		font-size: var(--fs-sm);
		line-height: var(--lh-sm);
		overflow-wrap: anywhere;
	}
	.detail {
		color: var(--text-2);
	}
	.tone-bad .detail {
		color: var(--bad);
	}
	.when {
		font-size: var(--fs-sm);
		line-height: var(--lh-sm);
		color: var(--text-2);
	}
	.more {
		align-self: center;
	}
	.sk {
		height: 160px;
	}
	.small-empty {
		padding: var(--sp-8) var(--sp-4);
	}
</style>
