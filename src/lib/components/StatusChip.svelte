<script lang="ts">
	import { CircleCheck, CircleDashed, CirclePause, Clock, ShieldAlert, TriangleAlert, XCircle } from '@lucide/svelte';
	import { LEVEL_LABEL, type ChipLevel } from '$lib/status';

	// Estado de un destino: siempre icono + texto (nunca solo color).
	let { level, label, size = 'sm' }: { level: ChipLevel; label?: string; size?: 'sm' | 'md' } = $props();

	const ICON = {
		ok: CircleCheck,
		late: Clock,
		overdue: TriangleAlert,
		failed: XCircle,
		empty: CircleDashed,
		paused: CirclePause,
		held: ShieldAlert
	};
	const Icon = $derived(ICON[level]);
	const text = $derived(label ?? (level === 'held' ? 'Cambio inusual' : LEVEL_LABEL[level]));
</script>

<span class="chip lvl-{level}" class:md={size === 'md'}><Icon size={size === 'md' ? 14 : 13} aria-hidden="true" />{text}</span>

<style>
	.md {
		padding: 0 11px;
		font-size: 12.5px;
		line-height: 28px;
	}
</style>
