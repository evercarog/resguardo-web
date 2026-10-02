<script lang="ts">
	import { ChevronDown, Server } from '@lucide/svelte';
	import InfoTip from '$lib/components/InfoTip.svelte';
	import { db } from '$lib/data.svelte';
	import type { BackupServer } from '$lib/types';

	// Servidor de copias de un equipo: puerto, alcance, equipos que lo usan y sus
	// repositorios (solo nombres). Nunca credenciales.
	let { server }: { server: BackupServer } = $props();

	const repos = $derived(server.users.reduce((n, u) => n + u.repos.length, 0));
	const deviceName = (id: string | null) => (id ? db.devices.find((d) => d.id === id)?.name : undefined);
	/** «AB:CD:EF…» para leerla y compararla con la de la app. */
	const fingerprint = $derived(server.tls_sha256 ? server.tls_sha256.match(/.{2}/g)!.join(':') : null);
</script>

<details class="server">
	<summary>
		<span class="ic" aria-hidden="true"><Server size={14} /></span>
		<span class="what">
			<strong>Servidor de copias</strong>
			<span class="faint num">
				· puerto {server.port} · {server.local_subnet_only ? 'solo red local' : 'abierto a otras sedes'} · {server.users.length}
				{server.users.length === 1 ? 'equipo' : 'equipos'} · {repos} {repos === 1 ? 'repositorio' : 'repositorios'}
			</span>
		</span>
		<InfoTip term="servidor-copias" />
		<span class="chev" aria-hidden="true"><ChevronDown size={14} /></span>
	</summary>
	<div class="body">
		<p class="faint line">
			Guarda las copias de tus otros equipos: cada uno solo ve su carpeta y no puede borrar nada. <a href="/ayuda#servidor-copias">Más</a>
		</p>
		<dl class="facts">
			<div>
				<dt>Direcciones</dt>
				<dd class="num">
					{#each server.lan_addresses as a}<span class="mono">{a.includes(':') ? `[${a}]` : a}:{server.port}</span>{:else}—{/each}
				</dd>
			</div>
			<div>
				<dt>Alcance</dt>
				<dd>{server.local_subnet_only ? 'Solo tu red local (el firewall limita el resto)' : 'Abierto a otras sedes (puerto abierto en el router)'}</dd>
			</div>
			{#if fingerprint}
				<div class="wide">
					<dt>Huella del certificado (SHA-256)</dt>
					<dd><code class="fp selectable">{fingerprint}</code></dd>
				</div>
			{/if}
		</dl>
		{#if server.users.length}
			<ul class="users">
				{#each server.users as u (u.user)}
					<li>
						<strong>{deviceName(u.device_id) ?? u.user}</strong>
						{#if deviceName(u.device_id)}<span class="faint">· usuario «{u.user}»</span>{/if}
						<span class="repos">{u.repos.length ? u.repos.join(', ') : 'sin repositorios todavía'}</span>
					</li>
				{/each}
			</ul>
		{:else}
			<p class="faint line">Todavía no lo usa ningún equipo.</p>
		{/if}
	</div>
</details>

<style>
	.server {
		background: var(--surface-2);
		border-radius: var(--radius);
	}
	summary {
		display: flex;
		align-items: center;
		gap: 8px;
		min-height: 36px;
		padding: 6px var(--sp-3);
		font-size: var(--fs-sm);
		line-height: var(--lh-sm);
		list-style: none;
		cursor: pointer;
	}
	summary::-webkit-details-marker {
		display: none;
	}
	.ic,
	.chev {
		display: grid;
		flex: none;
		color: var(--text-3);
	}
	.chev {
		margin-left: auto;
		transition: transform var(--dur) var(--ease);
	}
	details[open] .chev {
		transform: rotate(180deg);
	}
	.what {
		min-width: 0;
	}
	.what strong {
		font-weight: 500;
	}
	.body {
		display: flex;
		flex-direction: column;
		gap: var(--sp-3);
		padding: 0 var(--sp-3) var(--sp-3) calc(var(--sp-3) + 22px);
		font-size: var(--fs-sm);
		line-height: var(--lh-sm);
	}
	.facts {
		display: grid;
		grid-template-columns: repeat(2, minmax(0, 1fr));
		gap: var(--sp-3);
		margin: 0;
	}
	.facts .wide {
		grid-column: 1 / -1;
	}
	dt {
		font-size: var(--fs-xs);
		line-height: var(--lh-xs);
		font-weight: 500;
		color: var(--text-3);
	}
	dd {
		display: flex;
		flex-wrap: wrap;
		gap: 2px 10px;
		margin: 2px 0 0;
	}
	.fp {
		font-size: var(--fs-xs);
		word-break: break-all;
		color: var(--text-2);
	}
	.users {
		display: flex;
		flex-direction: column;
		gap: 6px;
		margin: 0;
		padding: 0;
		list-style: none;
	}
	.users li {
		display: flex;
		flex-wrap: wrap;
		gap: 2px 6px;
		padding-top: 6px;
		border-top: 1px solid var(--border);
	}
	.users strong {
		font-weight: 500;
	}
	.repos {
		flex-basis: 100%;
		color: var(--text-2);
		overflow-wrap: anywhere;
	}
	@media (max-width: 600px) {
		.facts {
			grid-template-columns: minmax(0, 1fr);
		}
		.body {
			padding-left: var(--sp-3);
		}
	}
</style>
