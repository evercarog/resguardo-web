<script lang="ts">
	import type { Snippet } from 'svelte';
	import Logo from './Logo.svelte';

	let { title, subtitle, children }: { title: string; subtitle?: string; children: Snippet } = $props();
</script>

<div class="wrap">
	<div class="glow" aria-hidden="true"></div>
	<div class="card box">
		<div class="head">
			<Logo size={52} />
			<h1>{title}</h1>
			{#if subtitle}<p class="muted">{subtitle}</p>{/if}
		</div>
		{@render children()}
	</div>
	<p class="foot faint">Resguardo · estado de tus copias con restic</p>
</div>

<style>
	.wrap {
		position: relative;
		isolation: isolate;
		display: flex;
		flex-direction: column;
		align-items: center;
		justify-content: center;
		gap: 18px;
		min-height: 100dvh;
		padding: 24px 16px;
	}
	.glow {
		position: absolute;
		top: 12%;
		left: 50%;
		width: 460px;
		height: 300px;
		translate: -50% 0;
		background: radial-gradient(closest-side, color-mix(in srgb, var(--accent) 20%, transparent), transparent);
		filter: blur(10px);
		z-index: -1;
	}
	.box {
		width: min(400px, 100%);
		padding: 28px 26px 24px;
		box-shadow: var(--shadow-md);
		animation: rise 0.35s cubic-bezier(0.2, 0.8, 0.2, 1) both;
	}
	.head {
		display: flex;
		flex-direction: column;
		align-items: center;
		text-align: center;
		gap: 8px;
		margin-bottom: 22px;
	}
	h1 {
		margin-top: 6px;
		font-size: 22px;
		font-weight: 700;
	}
	.head p {
		margin: 0;
		font-size: 14px;
		line-height: 1.5;
	}
	.foot {
		font-size: 12px;
	}
</style>
