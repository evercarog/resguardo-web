<script lang="ts">
	import { formatDate, formatRelative } from '$lib/format';

	// Tiempo relativo («hace 2 horas») con la fecha exacta al pasar el ratón
	// (y para los lectores de pantalla, en `datetime`).
	let { iso, now = Date.now(), capitalize = false }: { iso: string; now?: number; capitalize?: boolean } = $props();
	const text = $derived(formatRelative(iso, now));
</script>

<time datetime={iso} title={formatDate(iso)}>{capitalize ? text.charAt(0).toUpperCase() + text.slice(1) : text}</time>
