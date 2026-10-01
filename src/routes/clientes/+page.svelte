<script lang="ts">
	import { onMount } from 'svelte';
	import { Building2, CircleAlert, FileText, Pencil, Plus, Trash2 } from '@lucide/svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import { db, friendlyError, loadAll } from '$lib/data.svelte';
	import { supabase } from '$lib/supabase';
	import type { Client } from '$lib/types';

	let name = $state('');
	let error = $state('');
	/** Diálogo abierto: cambiar nombre o eliminar un cliente. */
	let dialog = $state<{ kind: 'rename' | 'remove'; client: Client } | null>(null);

	onMount(loadAll);

	const devicesOf = (c: Client) => db.devices.filter((d) => d.client_id === c.id).length;
	const reposOf = (c: Client) => {
		const ids = new Set(db.devices.filter((d) => d.client_id === c.id).map((d) => d.id));
		return db.repos.filter((r) => ids.has(r.device_id)).length;
	};

	async function add(e: SubmitEvent) {
		e.preventDefault();
		error = '';
		const n = name.trim();
		if (!n) return;
		const { error: err } = await supabase.from('clients').insert({ name: n });
		if (err) error = friendlyError(err.message);
		else name = '';
		await loadAll();
	}

	async function rename(c: Client, n: string) {
		if (n === c.name) return;
		const { error: err } = await supabase.from('clients').update({ name: n }).eq('id', c.id);
		if (err) throw new Error(friendlyError(err.message));
		await loadAll();
	}

	async function remove(c: Client) {
		const { error: err } = await supabase.from('clients').delete().eq('id', c.id);
		if (err) throw new Error(friendlyError(err.message));
		await loadAll();
	}

	function removeMessage(c: Client) {
		const n = devicesOf(c);
		if (!n) return 'Este cliente no tiene equipos.';
		return n === 1 ? 'Su equipo quedará como «Sin cliente».' : `Sus ${n} equipos quedarán como «Sin cliente».`;
	}
</script>

<svelte:head><title>Clientes · Resguardo</title></svelte:head>

<div class="page">
	<header>
		<h1>Clientes</h1>
		<p class="faint">Agrupa los equipos por cliente para verlos ordenados en el estado.</p>
	</header>

	<form class="card add" onsubmit={add}>
		<input class="input" bind:value={name} placeholder="Nombre del nuevo cliente" aria-label="Nombre del nuevo cliente" maxlength="80" />
		<button class="btn btn-primary" disabled={!name.trim()}><Plus size={16} /> Añadir</button>
	</form>
	{#if error || db.error}<div class="notice notice-danger"><CircleAlert size={16} /><p>{error || db.error}</p></div>{/if}

	<ul class="list">
		{#each db.clients as c, i (c.id)}
			<li class="card" style:--i={i}>
				<span class="ic"><Building2 size={17} /></span>
				<div class="info">
					<strong>{c.name}</strong>
					<span class="faint"
						>{devicesOf(c)} {devicesOf(c) === 1 ? 'equipo' : 'equipos'} · {reposOf(c)} {reposOf(c) === 1 ? 'destino' : 'destinos'}</span
					>
				</div>
				<a class="icon-btn" href="/informes?cliente={encodeURIComponent(c.id)}" title="Informe mensual" aria-label="Informe mensual de {c.name}"
					><FileText size={15} /></a
				>
				<button class="icon-btn" title="Cambiar nombre" aria-label="Cambiar nombre de {c.name}" onclick={() => (dialog = { kind: 'rename', client: c })}
					><Pencil size={15} /></button
				>
				<button class="icon-btn del" title="Eliminar" aria-label="Eliminar {c.name}" onclick={() => (dialog = { kind: 'remove', client: c })}
					><Trash2 size={15} /></button
				>
			</li>
		{:else}
			{#if db.loaded}
				<li class="faint none">Aún no hay clientes. Crea uno arriba y asígnale equipos desde Estado, en el menú «⋯» de cada equipo.</li>
			{:else if !db.error}
				{#each { length: 2 } as _}<li class="card skel-row" aria-hidden="true"><span class="skel"></span></li>{/each}
				<li class="sr-only" role="status">Cargando…</li>
			{/if}
		{/each}
	</ul>
</div>

{#if dialog?.kind === 'rename'}
	{@const c = dialog.client}
	<ConfirmDialog
		title="Cambiar nombre"
		inputLabel="Nombre del cliente"
		value={c.name}
		confirmLabel="Guardar"
		onconfirm={(n) => rename(c, n)}
		onclose={() => (dialog = null)}
	/>
{:else if dialog?.kind === 'remove'}
	{@const c = dialog.client}
	<ConfirmDialog
		title="¿Eliminar el cliente «{c.name}»?"
		message={removeMessage(c)}
		confirmLabel="Eliminar"
		danger
		onconfirm={() => remove(c)}
		onclose={() => (dialog = null)}
	/>
{/if}

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
		height: auto;
		align-self: stretch;
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
		line-height: 1.5;
		text-align: center;
	}
	.skel-row {
		padding: 14px;
	}
	.skel-row .skel {
		width: 45%;
		height: 30px;
	}
</style>
