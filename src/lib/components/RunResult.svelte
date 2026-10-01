<script lang="ts">
	import { CircleAlert, CircleCheck, TriangleAlert } from '@lucide/svelte';
	import RelTime from '$lib/components/RelTime.svelte';

	// Resultado de una ejecución (copia, verificación, subida…): icono, palabra y
	// cuándo, con la fecha exacta en el tooltip. Nunca solo color.
	type Run = { result: 'ok' | 'warning' | 'error'; started: string; finished?: string | null; unchanged?: boolean };
	let { run, now = Date.now(), empty = 'todavía ninguna' }: { run: Run | null | undefined; now?: number; empty?: string } = $props();

	const WORD = { ok: 'Correcta', warning: 'Con avisos', error: 'Falló' };
	const TONE = { ok: 'ok', warning: 'warn', error: 'bad' };
</script>

{#if run}
	<span class="run tone-{TONE[run.result]}">
		{#if run.result === 'ok'}<CircleCheck size={14} aria-hidden="true" />{:else if run.result === 'warning'}<TriangleAlert
				size={14}
				aria-hidden="true"
			/>{:else}<CircleAlert size={14} aria-hidden="true" />{/if}
		<span class="word">{run.result !== 'error' && run.unchanged ? 'Sin cambios' : WORD[run.result]}</span>
		<span class="when">· <RelTime iso={run.finished ?? run.started} {now} /></span>
	</span>
{:else}
	<span class="faint">{empty}</span>
{/if}

<style>
	.run {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		white-space: nowrap;
	}
	.run :global(svg) {
		flex: none;
		color: var(--tone);
	}
	.word {
		font-weight: 500;
		color: var(--tone);
	}
	.when {
		color: var(--text-3);
	}
</style>
