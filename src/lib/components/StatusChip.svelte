<script lang="ts">
	import { CircleAlert, CircleCheck, CircleDashed, CirclePause, TriangleAlert } from '@lucide/svelte';
	import { LEVEL_LABEL, LEVEL_TONE, type ChipLevel } from '$lib/status';

	// Chip de estado (diseño común): siempre icono + texto, nunca solo color.
	let { level, label, size = 'md' }: { level: ChipLevel; label?: string; size?: 'sm' | 'md' } = $props();

	const tone = $derived(LEVEL_TONE[level]);
	const ICON = { ok: CircleCheck, warn: TriangleAlert, bad: CircleAlert, paused: CirclePause, neutral: CircleDashed, info: CircleCheck };
	const Icon = $derived(ICON[tone]);
	const text = $derived(label ?? (level === 'held' ? 'Cambio inusual' : LEVEL_LABEL[level]));
</script>

<span class="badge tone-{tone}" class:badge-sm={size === 'sm'}><Icon size={12} strokeWidth={2.25} aria-hidden="true" />{text}</span>
