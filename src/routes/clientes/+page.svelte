<script lang="ts">
	import { onMount } from 'svelte';
	import { Building2, CircleAlert, Pencil, Plus, Trash2 } from '@lucide/svelte';
	import { db, loadAll } from '$lib/data.svelte';
	import { supabase } from '$lib/supabase';
	import type { Client } from '$lib/types';

	let name = $state('');
	let error = $state('');

	onMount(loadAll);

	const devicesOf = (c: Client) => db.devices.filter((d) => d.client_id === c.id).length;

	async function add(e: SubmitEvent) {
		e.preventDefault();
		error = '';
		const n = name.trim();
		if (!n) return;
		const { error: err } = await supabase.from('clients').insert({ name: n });
		if (err) error = err.message;
		else name = '';
		await loadAll();
	}

	async function rename(c: Client) {
		const n = prompt('Nombre del cliente', c.name)?.trim();
		if (!n || n === c.name) return;
		await supabase.from('clients').update({ name: n }).eq('id', c.id);
		await loadAll();
	}

	async function remove(c: Client) {
		const n = devicesOf(c);
		if (!confirm(`¿Eliminar el cliente «${c.name}»?${n ? ` Sus ${n} equipos quedarán como "Sin cliente".` : ''}`)) return;
		await supabase.from('clients').delete().eq('id', c.id);
		await loadAll();
	}
</script>

<svelte:head><title>Clientes · Resguardo</title></svelte:head>

<div class="page">
	<header>
		<h1>Clientes</h1>
		<p class="faint">Agrupa los equipos por cliente para verlos ordenados en el estado.</p>
	</header>

	<form class="card add" onsubmit={add}>
		<input class="input" bind:value={name} placeholder="Nombre del nuevo cliente" maxlength="80" />
		<button class="btn btn-primary" disabled={!name.trim()}><Plus size={16} /> Añadir</button>
	</form>
	{#if error}<div class="notice notice-danger"><CircleAlert size={16} /><p>{error}</p></div>{/if}

	<ul class="list">
		{#each db.clients as c, i (c.id)}
			<li class="card" style:--i={i}>
				<span class="ic"><Building2 size={17} /></span>
				<div class="info">
					<strong>{c.name}</strong>
					<span class="faint">{devicesOf(c)} {devicesOf(c) === 1 ? 'equipo' : 'equipos'}</span>
				</div>
				<button class="icon-btn" title="Cambiar nombre" onclick={() => rename(c)}><Pencil size={15} /></button>
				<button class="icon-btn del" title="Eliminar" onclick={() => remove(c)}><Trash2 size={15} /></button>
			</li>
		{:else}
			{#if db.loaded}<li class="faint none">Aún no hay clientes.</li>{/if}
		{/each}
	</ul>
</div>

<style>
	.page {
		display: flex;
		flex-direction: column;
		gap: 16px;
		max-width: 640px;
		margin: 0 auto;
	}
	h1 {
		font-size: 24px;
		font-weight: 700;
	}
	header p {
		margin: 4px 0 0;
		font-size: 13.5px;
	}
	.add {
		display: flex;
		gap: 8px;
		padding: 10px;
	}
	.add .btn {
		height: 36px;
	}
	.list {
		list-style: none;
		margin: 0;
		padding: 0;
		display: flex;
		flex-direction: column;
		gap: 8px;
	}
	.list li.card {
		display: flex;
		align-items: center;
		gap: 12px;
		padding: 12px 14px;
		animation: rise 0.3s cubic-bezier(0.2, 0.8, 0.2, 1) both;
		animation-delay: calc(var(--i) * 30ms);
	}
	.ic {
		display: grid;
		place-items: center;
		width: 34px;
		height: 34px;
		border-radius: 9px;
		color: var(--accent-soft-text);
		background: var(--accent-soft);
	}
	.info {
		display: flex;
		flex-direction: column;
		flex: 1;
		min-width: 0;
	}
	.info .faint {
		font-size: 12.5px;
	}
	.del:hover {
		color: var(--danger);
	}
	.none {
		padding: 20px;
		text-align: center;
	}
</style>
