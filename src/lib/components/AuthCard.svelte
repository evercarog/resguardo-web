<script lang="ts">
	import type { Snippet } from 'svelte';
	import Logo from './Logo.svelte';

	let { title, subtitle, children }: { title: string; subtitle?: string; children: Snippet } = $props();
</script>

<div class="wrap">
	<div class="card box">
		<div class="head">
			<Logo size={44} />
			<h1>{title}</h1>
			{#if subtitle}<p class="muted">{subtitle}</p>{/if}
		</div>
		{@render children()}
	</div>
	<p class="foot faint">Resguardo · estado de tus copias con restic</p>
</div>

<style>
	.wrap {
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: var(--sp-5);
		min-height: 100dvh;
		padding: var(--sp-6) var(--sp-4);
		background: var(--bg-subtle);
	}
	.box {
		width: min(400px, 100%);
		padding: var(--sp-8);
		border-radius: var(--radius-xl);
		box-shadow: var(--shadow-sm);
		animation: rise var(--dur-slow) var(--ease-out) both;
	}
	.head {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: var(--sp-2);
		margin-bottom: var(--sp-6);
		text-align: center;
	}
	h1 {
		margin-top: var(--sp-2);
		font-size: var(--fs-title);
		line-height: var(--lh-title);
		font-weight: 650;
		letter-spacing: -0.018em;
	}
	.head p {
		font-size: var(--fs-sm);
		line-height: var(--lh-sm);
	}
	.foot {
		font-size: var(--fs-xs);
		line-height: var(--lh-xs);
	}
	@media (max-width: 480px) {
		.box {
			padding: var(--sp-6) var(--sp-5);
		}
	}
</style>
