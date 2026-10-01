<script lang="ts">
	import { protectionSummary } from '$lib/status';
	import type { Protection } from '$lib/types';

	// Anillo de la salud de la protección («5 de 7»), como en la app de escritorio.
	let { protection, size = 18 }: { protection: Protection; size?: number } = $props();

	const sum = $derived(protectionSummary(protection));
	/** Circunferencia de r = 26. */
	const C = 2 * Math.PI * 26;
</script>

<svg class="ring tone-{sum.tone}" width={size} height={size} viewBox="0 0 64 64" aria-hidden="true">
	<circle cx="32" cy="32" r="26" class="track" />
	{#if sum.ratio > 0}<circle cx="32" cy="32" r="26" class="arc" stroke-dasharray="{C * sum.ratio} {C}" transform="rotate(-90 32 32)" />{/if}
</svg>

<style>
	.ring {
		flex: none;
	}
	.track {
		fill: none;
		stroke: var(--surface-3);
		stroke-width: 8;
	}
	.arc {
		fill: none;
		stroke: var(--tone);
		stroke-width: 8;
		stroke-linecap: round;
		transition: stroke-dasharray 0.6s cubic-bezier(0.2, 0.8, 0.2, 1);
	}
	.tone-ok {
		--tone: var(--success);
	}
	.tone-warn {
		--tone: var(--warn);
	}
	.tone-bad {
		--tone: var(--danger);
	}
</style>
