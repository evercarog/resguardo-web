<script lang="ts">
	import { protectionSummary } from '$lib/status';
	import type { Protection } from '$lib/types';

	// Anillo de protección (diseño común): pista neutra y arco del tono global.
	// Grosor 7 sobre 64, proporcional en cualquier tamaño.
	let { protection, size = 18 }: { protection: Protection; size?: number } = $props();

	const sum = $derived(protectionSummary(protection));
	/** Circunferencia de r = 28.5 (64 − 7, a la mitad). */
	const R = 28.5;
	const C = 2 * Math.PI * R;
</script>

<svg class="ring tone-{sum.tone}" width={size} height={size} viewBox="0 0 64 64" aria-hidden="true">
	<circle cx="32" cy="32" r={R} class="track" />
	{#if sum.ratio > 0}<circle cx="32" cy="32" r={R} class="arc" stroke-dasharray="{C * sum.ratio} {C}" transform="rotate(-90 32 32)" />{/if}
</svg>

<style>
	.ring {
		flex: none;
	}
	.track {
		fill: none;
		stroke: var(--surface-3);
		stroke-width: 7;
	}
	.arc {
		fill: none;
		stroke: var(--tone);
		stroke-width: 7;
		stroke-linecap: round;
		transition: stroke-dasharray var(--dur-slow) var(--ease-out);
	}
</style>
