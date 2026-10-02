<script lang="ts">
	import { CircleQuestionMark } from '@lucide/svelte';
	import { GLOSSARY } from '$lib/glossary';

	// «?» junto a un término, estado, cifra o comprobación: qué es y qué hacer
	// (textos del glosario). Se abre al pasar el ratón, al enfocar o al tocar.
	let { term, text, label }: { term?: string; text?: string; label?: string } = $props();
	const uid = $props.id();
	let open = $state(false);
	const entry = $derived(term ? GLOSSARY[term] : undefined);
	const aria = $derived(label ?? (entry ? `Qué significa «${entry.title}»` : 'Qué significa'));
</script>

<span class="tip-wrap" role="presentation" onmouseenter={() => (open = true)} onmouseleave={() => (open = false)}>
	<button
		type="button"
		class="tip-btn"
		aria-label={aria}
		aria-describedby={open ? `tip-${uid}` : undefined}
		aria-expanded={open}
		onclick={() => (open = !open)}
		onfocus={() => (open = true)}
		onblur={(e) => {
			if (!(e.currentTarget.parentElement?.contains(e.relatedTarget as Node | null) ?? false)) open = false;
		}}
		onkeydown={(e) => e.key === 'Escape' && (open = false)}
	>
		<CircleQuestionMark size={14} aria-hidden="true" />
	</button>
	{#if open}
		<span class="tip" role="tooltip" id="tip-{uid}">
			{#if entry}
				<strong>{entry.title}</strong>
				<span>{entry.text}</span>
				{#if entry.todo}<span><em>Qué hacer:</em> {entry.todo}</span>{/if}
				<a href="/ayuda#{term}" onblur={() => (open = false)}>Más en «Qué significa cada cosa»</a>
			{:else}
				<span>{text}</span>
			{/if}
		</span>
	{/if}
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
		top: 100%;
		left: -8px;
		z-index: 20;
		display: flex;
		flex-direction: column;
		gap: 4px;
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
	.tip strong {
		font-weight: 600;
	}
	.tip em {
		font-style: normal;
		font-weight: 600;
	}
	.tip a {
		color: inherit;
		text-decoration: underline;
		text-underline-offset: 2px;
		opacity: 0.85;
	}
	@media (max-width: 720px) {
		.tip {
			left: auto;
			right: -8px;
		}
	}
	@media print {
		.tip-wrap {
			display: none !important;
		}
	}
</style>
