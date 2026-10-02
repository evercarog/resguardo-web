<script lang="ts">
	import { CircleQuestionMark } from '@lucide/svelte';

	// Explicación breve junto a un término (al pasar el ratón, al enfocar o al tocar).
	let { text, label = 'Qué significa' }: { text: string; label?: string } = $props();
	const uid = $props.id();
	let open = $state(false);
</script>

<span class="tip-wrap">
	<button
		type="button"
		class="tip-btn"
		aria-label={label}
		aria-describedby={open ? `tip-${uid}` : undefined}
		aria-expanded={open}
		onclick={() => (open = !open)}
		onmouseenter={() => (open = true)}
		onmouseleave={() => (open = false)}
		onfocus={() => (open = true)}
		onblur={() => (open = false)}
		onkeydown={(e) => e.key === 'Escape' && (open = false)}
	>
		<CircleQuestionMark size={14} aria-hidden="true" />
	</button>
	{#if open}<span class="tip" role="tooltip" id="tip-{uid}">{text}</span>{/if}
</span>

<style>
	.tip-wrap {
		position: relative;
		display: inline-flex;
		vertical-align: middle;
	}
	.tip-btn {
		display: inline-grid;
		place-items: center;
		width: 20px;
		height: 20px;
		padding: 0;
		color: var(--text-3);
		background: none;
		border: none;
		border-radius: 999px;
		cursor: help;
	}
	.tip-btn:hover {
		color: var(--text-1);
	}
	/* Tooltip del diseño común: fondo de texto, letra pequeña, 280 de ancho como mucho. */
	.tip {
		position: absolute;
		top: calc(100% + 6px);
		left: -8px;
		z-index: 20;
		width: max-content;
		max-width: min(280px, 80vw);
		padding: 8px 10px;
		font-size: var(--fs-xs);
		line-height: var(--lh-xs);
		font-weight: 400;
		text-align: left;
		letter-spacing: 0;
		text-transform: none;
		white-space: normal;
		color: var(--bg);
		background: var(--text-1);
		border-radius: var(--radius-sm);
		box-shadow: var(--shadow-md);
		animation: rise var(--dur) var(--ease-out) both;
	}
	@media (max-width: 720px) {
		.tip {
			left: auto;
			right: -8px;
		}
	}
</style>
