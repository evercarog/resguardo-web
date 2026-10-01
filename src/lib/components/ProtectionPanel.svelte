<script lang="ts">
	import { onMount } from 'svelte';
	import { CircleAlert, CircleCheck, CircleQuestionMark, CircleX, KeyRound, ShieldCheck } from '@lucide/svelte';
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
				<ProtectionRing protection={p} size={74} />
				<span class="score" aria-hidden="true"><strong>{p.score}</strong><span>de {p.total}</span></span>
			</div>
			<div class="sum-text">
				<h2 id="proteccion-titulo"><ShieldCheck size={16} aria-hidden="true" /> Salud de la protección</h2>
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
						{#if i.state === 'ok'}<CircleCheck size={17} aria-hidden="true" />{:else if i.state === 'warn'}<CircleAlert
								size={17}
								aria-hidden="true"
							/>{:else if i.state === 'bad'}<CircleX size={17} aria-hidden="true" />{:else}<CircleQuestionMark size={17} aria-hidden="true" />{/if}
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
		gap: 14px;
		padding: 18px 20px;
		scroll-margin-top: calc(var(--header-h, 60px) + 16px);
	}
	.summary {
		display: flex;
		align-items: center;
		gap: 16px;
	}
	.ring-wrap {
		position: relative;
		display: grid;
		place-items: center;
		flex: none;
	}
	.score {
		position: absolute;
		display: flex;
		flex-direction: column;
		align-items: center;
		line-height: 1;
	}
	.score strong {
		font-family: var(--font-display);
		font-size: 22px;
	}
	.score span {
		font-size: 11px;
		color: var(--text-3);
	}
	.sum-text {
		display: flex;
		flex-direction: column;
		gap: 3px;
		min-width: 0;
	}
	h2 {
		display: flex;
		align-items: center;
		gap: 7px;
		font-size: 16px;
		font-weight: 650;
	}
	.sum-text p {
		margin: 0;
		font-size: 13px;
		line-height: 1.5;
	}
	.items {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(min(100%, 320px), 1fr));
		gap: 6px;
		margin: 0;
		padding: 0;
		list-style: none;
	}
	.item {
		display: flex;
		align-items: center;
		gap: 10px;
		min-width: 0;
		padding: 9px 10px 9px 12px;
		background: var(--surface-2);
		border: 1px solid var(--border);
		border-radius: var(--radius);
	}
	.ic {
		display: grid;
		flex: none;
	}
	.st-ok .ic {
		color: var(--success);
	}
	.st-warn .ic {
		color: var(--warn);
	}
	.st-bad .ic {
		color: var(--danger);
	}
	.st-unknown .ic {
		color: var(--text-3);
	}
	.txt {
		display: flex;
		flex-direction: column;
		min-width: 0;
		font-size: 13px;
		line-height: 1.4;
	}
	.txt strong {
		font-weight: 600;
	}
	.txt .faint {
		font-size: 12.5px;
		overflow-wrap: anywhere;
	}
	.kit {
		display: flex;
		align-items: center;
		gap: 6px;
		margin: 0;
		font-size: 12.5px;
	}
</style>
