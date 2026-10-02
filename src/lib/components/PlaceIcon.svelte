<script lang="ts">
	import { Cloud, Database, FolderSync, HardDrive, Server } from '@lucide/svelte';

	// Icono de un destino según su tipo.
	let { kind, size = 16 }: { kind: string; size?: number } = $props();
	const Icon = $derived(
		['s3', 'b2', 'azure', 'gs'].includes(kind) ? Cloud : ['rest', 'sftp'].includes(kind) ? Server : kind === 'local' ? HardDrive : kind === 'rclone' ? FolderSync : Database
	);
</script>

<Icon {size} aria-hidden="true" />
