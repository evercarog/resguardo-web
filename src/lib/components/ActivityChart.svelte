<script lang="ts" generics="T extends { time: string }">
	import { formatDate } from '$lib/format';

	// Una sola serie por gráfica (sin doble eje): barras finas ancladas a la
	// base, detalle al pasar el dedo o el ratón.
	interface Props {
		title: string;
		/** Snapshots de más reciente a más antiguo (se muestran los últimos 30). */
		items: T[];
		value: (item: T) => number | null | undefined;
		format: (v: number) => string;
	}
	let { title, items, value, format }: Props = $props();

	const points = $derived(
		items
			.filter((i) => value(i) != null)
			.slice(0, 30)
			.reverse()
			.map((i) => ({ time: i.time, v: value(i) ?? 0 }))
	);
	const max = $derived(Math.max(1, ...points.map((p) => p.v)));
	let hover = $state<number | null>(null);

	/** Posición del detalle: en los extremos se ancla al borde para no salirse. */
	const tip = $derived.by(() => {
		if (hover === null) return null;
		const f = (hover + 0.5) / points.length;
		if (f < 0.25) return { align: 'start', left: '0', right: 'auto' };
		if (f > 0.75) return { align: 'end', left: 'auto', right: '0' };
		return { align: 'center', left: `${f * 100}%`, right: 'auto' };
	});
</script>

{#if points.length >= 2}
	<figure>
		<figcaption>
			<span>{title}</span>
			<span class="faint">máx. {format(max)}</span>
		</figcaption>
		<div class="plot" role="img" aria-label="{title}, últimas {points.length} versiones" onmouseleave={() => (hover = null)}>
			{#each points as p, i}
				<button
					class="col"
					class:on={hover === i}
					onmouseenter={() => (hover = i)}
					onfocus={() => (hover = i)}
					onclick={() => (hover = hover === i ? null : i)}
					aria-label="{formatDate(p.time)}: {format(p.v)}"
				>
					<span class="bar" style:height="{Math.max(2, (p.v / max) * 100)}%" style:--i={i}></span>
				</button>
			{/each}
			{#if hover !== null && tip}
				<div class="tip {tip.align}" style:left={tip.left} style:right={tip.right}>
					<strong>{format(points[hover].v)}</strong>
					<span>{formatDate(points[hover].time)}</span>
				</div>
			{/if}
		</div>
		<div class="axis faint">
			<span>{formatDate(points[0].time)}</span>
			<span>{formatDate(points.at(-1)!.time)}</span>
		</div>
	</figure>
{/if}

<style>
	figure {
		margin: 0;
		min-width: 0;
	}
	figcaption {
		display: flex;
		justify-content: space-between;
		margin-bottom: 8px;
		font-size: 12.5px;
		font-weight: 600;
		color: var(--text-2);
	}
	figcaption .faint {
		font-weight: 400;
	}
	.plot {
		position: relative;
		display: flex;
		align-items: flex-end;
		gap: 2px;
		height: 88px;
		border-bottom: 1px solid var(--border-strong);
	}
	.col {
		flex: 1;
		display: flex;
		align-items: flex-end;
		height: 100%;
		padding: 0;
		background: none;
		border: none;
	}
	.bar {
		width: 100%;
		border-radius: 4px 4px 0 0;
		background: var(--accent);
		opacity: 0.75;
		transform-origin: bottom;
		animation: grow 0.45s cubic-bezier(0.2, 0.8, 0.2, 1) both;
		animation-delay: calc(var(--i) * 12ms);
	}
	.col.on .bar {
		opacity: 1;
	}
	.plot:hover .col:not(.on) .bar {
		opacity: 0.45;
	}
	@keyframes grow {
		from {
			transform: scaleY(0);
		}
	}
	.tip {
		position: absolute;
		bottom: calc(100% + 6px);
		z-index: 2;
		display: flex;
		flex-direction: column;
		align-items: center;
		padding: 5px 9px;
		font-size: 12px;
		white-space: nowrap;
		background: var(--surface);
		border: 1px solid var(--border-strong);
		border-radius: 7px;
		box-shadow: var(--shadow-md);
		pointer-events: none;
	}
	.tip.center {
		translate: -50% 0;
	}
	.tip.start {
		align-items: flex-start;
	}
	.tip.end {
		align-items: flex-end;
	}
	.tip span {
		color: var(--text-3);
		font-size: 11.5px;
	}
	.axis {
		display: flex;
		justify-content: space-between;
		margin-top: 5px;
		font-size: 11.5px;
	}
</style>
