<script lang="ts">
	import { onMount } from 'svelte';
	import { CircleAlert, CircleCheck, CircleDashed, KeyRound, TriangleAlert } from '@lucide/svelte';
	import ProtectionRing from '$lib/components/ProtectionRing.svelte';
	import RelTime from '$lib/components/RelTime.svelte';
	import { protectionSummary } from '$lib/status';
	import type { Repo } from '$lib/types';

	// «Salud de la protección» de un destino, tal como la calcula la app de
	// escritorio: un anillo «5 de 7» y la lista de comprobaciones. Solo lectura:
	// lo que falte se arregla en Resguardo, en el equipo.
	let { repo, now }: { repo: Repo; now: number } = $props();

	const p = $derived(repo.protection ?? null);
	const sum = $derived(p ? protectionSummary(p) : null);
	/** Estado en palabras, para quien no distingue los colores o usa lector de pantalla. */
	const WORD = { ok: 'Bien', warn: 'Por revisar', bad: 'Falta', unknown: 'Sin comprobar' };

	// Al llegar desde la tarjeta de Estado (#proteccion), se lleva a la vista.
	onMount(() => {
		if (location.hash === '#proteccion') requestAnimationFrame(() => document.getElementById('proteccion')?.scrollIntoView({ block: 'start' }));
	});
</script>

{#if p && sum}
	<section class="card health tone-{sum.tone}" id="proteccion" aria-labelledby="proteccion-titulo">
		<div class="summary">
			<div class="ring-wrap">
				<ProtectionRing protection={p} size={64} />
				<span class="score num" aria-hidden="true">{p.score}<span class="tot">/{p.total}</span></span>
			</div>
			<div class="sum-text">
				<h2 class="section-title" id="proteccion-titulo">Salud de la protección</h2>
				<p class="faint">
					<span class="sr-only">{p.score} de {p.total}.</span>
					{#if !sum.issues}
						Todo en orden: las copias de «{repo.name}» están protegidas por todos los frentes.
					{:else}
						{sum.issues === 1 ? 'Falta una cosa' : `Faltan ${sum.issues} cosas`} para que las copias de «{repo.name}» estén protegidas del
						todo. Se arregla en Resguardo, en el equipo.
					{/if}
				</p>
			</div>
		</div>

		<ul class="items">
			{#each p.items as i (i.id)}
				<li class="item st-{i.state}">
					<span class="ic" title={WORD[i.state]}>
						{#if i.state === 'ok'}<CircleCheck size={16} aria-hidden="true" />{:else if i.state === 'warn'}<TriangleAlert
								size={16}
								aria-hidden="true"
							/>{:else if i.state === 'bad'}<CircleAlert size={16} aria-hidden="true" />{:else}<CircleDashed size={16} aria-hidden="true" />{/if}
					</span>
					<span class="txt">
						<strong>{i.label}<span class="sr-only">: {WORD[i.state]}</span></strong>
						{#if i.detail}<span class="faint">{i.detail}</span>{/if}
					</span>
				</li>
			{/each}
		</ul>

		{#if repo.kit_saved_at}
			<p class="faint kit"><KeyRound size={13} aria-hidden="true" /><span>Kit de recuperación guardado <RelTime iso={repo.kit_saved_at} {now} />.</span></p>
		{/if}
	</section>
{/if}

<style>
	.health {
		display: flex;
		flex-direction: column;
		gap: var(--sp-4);
		padding: var(--sp-5);
		scroll-margin-top: calc(var(--header-h, 56px) + 16px);
	}
	.summary {
		display: flex;
		align-items: center;
		gap: var(--sp-4);
	}
	.ring-wrap {
		position: relative;
		display: grid;
		flex: none;
		place-items: center;
	}
	.score {
		position: absolute;
		font-size: var(--fs-h2);
		line-height: var(--lh-h2);
		font-weight: 600;
	}
	.score .tot {
		margin-left: 2px;
		font-weight: 400;
		color: var(--text-3);
	}
	.sum-text {
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
	}
	.sum-text p {
		font-size: var(--fs-sm);
		line-height: var(--lh-sm);
	}
	.items {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(min(100%, 300px), 1fr));
		gap: var(--sp-2);
		margin: 0;
		padding: 0;
		list-style: none;
	}
	.item {
		display: flex;
		align-items: flex-start;
		gap: var(--sp-3);
		min-width: 0;
		padding: var(--sp-3);
		background: var(--surface-2);
		border-radius: var(--radius);
	}
	.ic {
		display: grid;
		flex: none;
		padding-top: 2px;
	}
	.st-ok .ic {
		color: var(--ok);
	}
	.st-warn .ic {
		color: var(--warn);
	}
	.st-bad .ic {
		color: var(--bad);
	}
	.st-unknown .ic {
		color: var(--neutral);
	}
	.txt {
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
	}
	.txt strong {
		font-weight: 500;
	}
	.txt .faint {
		font-size: var(--fs-sm);
		line-height: var(--lh-sm);
		overflow-wrap: anywhere;
	}
	.kit {
		display: flex;
		align-items: center;
		gap: 6px;
		font-size: var(--fs-sm);
		line-height: var(--lh-sm);
	}
</style>
