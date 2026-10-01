<script lang="ts">
	import type { DayCell } from '$lib/status';

	// Cuadros de actividad por día (diseño común): el más reciente a la derecha.
	// Copia con datos = bien al 85 %, «sin cambios» = bien al 45 %, avisos, fallo,
	// sin copia = pista neutra. Cada cuadro lleva la fecha y el resultado.
	let {
		days,
		size = 'md',
		selected = null,
		onselect,
		label
	}: { days: DayCell[]; size?: 'md' | 'mini'; selected?: string | null; onselect?: (key: string | null) => void; label: string } = $props();
</script>

<div class="squares {size}" role={onselect ? 'group' : 'img'} aria-label={label}>
	{#each days as d (d.key)}
		{#if onselect}
			<button
				type="button"
				class="sq s-{d.state}"
				class:on={selected === d.key}
				title={d.title}
				aria-label={d.title}
				aria-pressed={selected === d.key}
				disabled={d.n === 0}
				onclick={() => onselect(selected === d.key ? null : d.key)}
			></button>
		{:else}
			<span class="sq s-{d.state}" title={d.title}></span>
		{/if}
	{/each}
</div>

<style>
	.squares {
		--sq: 10px;
		display: flex;
		flex-wrap: wrap;
		gap: 3px;
	}
	.squares.mini {
		--sq: 8px;
		flex-wrap: nowrap;
	}
	.sq {
		flex: none;
		width: var(--sq);
		height: var(--sq);
		padding: 0;
		border: none;
		border-radius: 2px;
		background: var(--surface-3);
	}
	button.sq {
		cursor: pointer;
	}
	button.sq:disabled {
		cursor: default;
	}
	.s-data {
		background: color-mix(in srgb, var(--ok) 85%, transparent);
	}
	.s-same {
		background: color-mix(in srgb, var(--ok) 45%, transparent);
	}
	.s-warn {
		background: var(--warn);
	}
	.s-bad {
		background: var(--bad);
	}
	.s-future {
		background: transparent;
		box-shadow: inset 0 0 0 1px var(--border);
	}
	.sq.on {
		outline: 2px solid var(--text-1);
		outline-offset: 1px;
	}
</style>
