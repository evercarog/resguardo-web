<script lang="ts">
	import { CircleAlert, CircleCheck, TriangleAlert } from '@lucide/svelte';
	import RelTime from '$lib/components/RelTime.svelte';

	// Resultado de una ejecución (copia, verificación, subida): icono, palabra y
	// cuándo, con la fecha exacta al pasar el ratón. Nunca solo color.
	type Run = { result: 'ok' | 'warning' | 'error'; started: string; finished?: string | null; unchanged?: boolean };
	let { run, now = Date.now(), empty = 'todavía ninguna' }: { run: Run | null | undefined; now?: number; empty?: string } = $props();

	const WORD = { ok: 'Correcta', warning: 'Con avisos', error: 'Falló' };
</script>

{#if run}
	<span class="run run-{run.result}">
		{#if run.result === 'ok'}<CircleCheck size={13} aria-hidden="true" />{:else if run.result === 'warning'}<TriangleAlert
				size={13}
				aria-hidden="true"
			/>{:else}<CircleAlert size={13} aria-hidden="true" />{/if}
		{run.result !== 'error' && run.unchanged ? 'Sin cambios' : WORD[run.result]} · <RelTime iso={run.finished ?? run.started} {now} />
	</span>
{:else}
	<span class="faint">{empty}</span>
{/if}

<style>
	.run {
		display: inline-flex;
		align-items: center;
		gap: 5px;
		font-weight: 600;
		white-space: nowrap;
	}
	.run :global(svg) {
		flex: none;
	}
	.run-ok {
		color: var(--success);
	}
	.run-warning {
		color: var(--warn);
	}
	.run-error {
		color: var(--danger);
	}
</style>
