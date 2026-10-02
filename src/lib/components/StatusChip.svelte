<script lang="ts">
	import { CircleAlert, CircleCheck, CircleDashed, CirclePause, TriangleAlert } from '@lucide/svelte';
	import InfoTip from '$lib/components/InfoTip.svelte';
	import { LEVEL_TERM } from '$lib/glossary';
	import { LEVEL_LABEL, LEVEL_TONE, type ChipLevel } from '$lib/status';

	// Chip de estado (diseño común): siempre icono + texto, nunca solo color.
	let { level, label, size = 'md', tip = false }: { level: ChipLevel; label?: string; size?: 'sm' | 'md'; tip?: boolean } = $props();

	const tone = $derived(LEVEL_TONE[level]);
	const ICON = { ok: CircleCheck, warn: TriangleAlert, bad: CircleAlert, paused: CirclePause, neutral: CircleDashed, info: CircleCheck };
	const Icon = $derived(ICON[tone]);
	const text = $derived(label ?? (level === 'held' ? 'Cambio inusual' : LEVEL_LABEL[level]));
</script>

{#if tip}
	<span class="with-tip">
		<span class="badge tone-{tone}" class:badge-sm={size === 'sm'}><Icon size={12} strokeWidth={2.25} aria-hidden="true" />{text}</span>
		<InfoTip term={LEVEL_TERM[level]} />
	</span>
{:else}
	<span class="badge tone-{tone}" class:badge-sm={size === 'sm'}><Icon size={12} strokeWidth={2.25} aria-hidden="true" />{text}</span>
{/if}

<style>
	.with-tip {
		display: inline-flex;
		flex: none;
		align-items: center;
		gap: 2px;
	}
</style>
