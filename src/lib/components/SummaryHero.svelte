<script lang="ts">
	import { ArrowRight, CircleAlert, LoaderCircle, RefreshCw, ShieldCheck, TriangleAlert } from '@lucide/svelte';
	import type { UrgentItem } from '$lib/attention';
	import InfoTip from '$lib/components/InfoTip.svelte';
	import { REPO_TIP } from '$lib/status';

	// Resumen grande del inicio (diseño común): un titular, una línea de
	// resumen y lo urgente, ordenado, cada punto con su acción.
	let {
		items,
		summary,
		running,
		updated,
		refreshing,
		onrefresh
	}: {
		items: UrgentItem[];
		summary: string;
		/** «Copiando ahora en 2 destinos», si hay algo en marcha. */
		running: string;
		updated: string;
		refreshing: boolean;
		onrefresh: () => void;
	} = $props();

	const LIMIT = 6;
	let all = $state(false);
	const shown = $derived(all ? items : items.slice(0, LIMIT));
	const tone = $derived(items.some((i) => i.tone === 'bad') ? 'bad' : items.length ? 'warn' : 'ok');
	const headline = $derived(
		items.length ? `${items.length} ${items.length === 1 ? 'cosa necesita' : 'cosas necesitan'} atención` : 'Todo protegido'
	);
</script>

<section class="hero tone-{tone}" aria-labelledby="hero-title">
	<div class="head">
		<span class="badge-ic" aria-hidden="true">
			{#if tone === 'ok'}<ShieldCheck size={22} />{:else if tone === 'bad'}<CircleAlert size={22} />{:else}<TriangleAlert size={22} />{/if}
		</span>
		<div class="text">
			<h1 id="hero-title">{headline}</h1>
			<p class="sub num">{summary} <InfoTip text={REPO_TIP} label="Qué son los destinos y los repositorios" /></p>
			{#if running}
				<p class="running"><span class="spin"><LoaderCircle size={14} aria-hidden="true" /></span>{running}</p>
			{/if}
		</div>
		<div class="tools">
			{#if updated}<span class="updated">{updated}</span>{/if}
			<button class="icon-btn" onclick={onrefresh} disabled={refreshing} title="Actualizar" aria-label="Actualizar">
				<span class:spin={refreshing} style="display:grid"><RefreshCw size={16} /></span>
			</button>
		</div>
	</div>

	{#if items.length}
		<ul class="list">
			{#each shown as i (i.key)}
				<li class="item tone-{i.tone}">
					<span class="ic" aria-hidden="true">{#if i.tone === 'bad'}<CircleAlert size={16} />{:else}<TriangleAlert size={16} />{/if}</span>
					<div class="main">
						<p class="t">{i.title}</p>
						{#if i.detail}<p class="d">{i.detail}</p>{/if}
						{#if i.advice}<p class="advice">{i.advice}</p>{/if}
						<p class="w">{i.where}</p>
					</div>
					<a class="btn btn-sm act" href={i.href}>{i.action} <ArrowRight size={14} aria-hidden="true" /></a>
				</li>
			{/each}
		</ul>
		{#if items.length > LIMIT}
			<button class="btn btn-ghost btn-sm more" onclick={() => (all = !all)} aria-expanded={all}>
				{all ? 'Ver menos' : `Ver ${items.length - LIMIT} más`}
			</button>
		{/if}
	{/if}
</section>

<style>
	.hero {
		display: flex;
		flex-direction: column;
		gap: var(--sp-5);
		padding: var(--sp-8);
		background: var(--surface);
		border: 1px solid var(--border);
		border-radius: var(--radius-xl);
		animation: rise var(--dur-slow) var(--ease-out) both;
	}
	.head {
		display: flex;
		align-items: flex-start;
		gap: var(--sp-4);
	}
	.badge-ic {
		display: grid;
		flex: none;
		place-items: center;
		width: 44px;
		height: 44px;
		color: var(--tone);
		background: var(--tone-soft);
		border-radius: 999px;
	}
	.text {
		display: flex;
		flex: 1;
		flex-direction: column;
		gap: 4px;
		min-width: 0;
	}
	h1 {
		font-size: var(--fs-display);
		line-height: var(--lh-display);
		font-weight: 650;
		letter-spacing: -0.022em;
	}
	.sub {
		font-size: var(--fs-body);
		line-height: var(--lh-body);
		color: var(--text-2);
	}
	.running {
		display: flex;
		align-items: center;
		gap: 6px;
		font-size: var(--fs-sm);
		line-height: var(--lh-sm);
		color: var(--info);
	}
	.tools {
		display: flex;
		flex: none;
		align-items: center;
		gap: var(--sp-2);
	}
	.updated {
		font-size: var(--fs-xs);
		line-height: var(--lh-xs);
		color: var(--text-3);
	}
	.list {
		margin: 0;
		padding: 0;
		list-style: none;
		border-top: 1px solid var(--border);
	}
	.item {
		display: grid;
		grid-template-columns: 16px minmax(0, 1fr) auto;
		align-items: start;
		gap: var(--sp-3);
		min-height: 44px;
		padding: var(--sp-3) 0;
		border-bottom: 1px solid var(--border);
	}
	.ic {
		display: grid;
		padding-top: 2px;
		color: var(--tone);
	}
	.main {
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
	}
	.t {
		font-weight: 500;
		overflow-wrap: anywhere;
	}
	.d,
	.advice,
	.w {
		font-size: var(--fs-sm);
		line-height: var(--lh-sm);
		overflow-wrap: anywhere;
	}
	.d {
		color: var(--text-2);
	}
	.advice {
		color: var(--text-2);
	}
	.w {
		color: var(--text-3);
	}
	.act {
		align-self: center;
	}
	.more {
		align-self: flex-start;
		margin-top: calc(-1 * var(--sp-2));
	}
	@media (max-width: 720px) {
		.hero {
			gap: var(--sp-4);
			padding: var(--sp-5);
			border-radius: var(--radius-lg);
		}
		.head {
			flex-wrap: wrap;
			gap: var(--sp-3);
		}
		.badge-ic {
			width: 36px;
			height: 36px;
		}
		.text {
			flex-basis: calc(100% - 52px);
		}
		.hero {
			position: relative;
		}
		.text {
			padding-right: 36px;
		}
		.tools {
			position: absolute;
			top: var(--sp-4);
			right: var(--sp-3);
		}
		.updated {
			display: none;
		}
		.item {
			grid-template-columns: 16px minmax(0, 1fr);
		}
		.act {
			grid-column: 2;
			justify-self: start;
		}
	}
</style>
