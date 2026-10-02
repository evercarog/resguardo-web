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
	<header class="page-head">
		<div>
			<h1 class="page-title">Clientes</h1>
			<p class="page-sub">Agrupa los equipos por cliente para verlos ordenados en el estado y en los informes.</p>
		</div>
	</header>

	<form class="add" onsubmit={add}>
		<input class="input" bind:value={name} placeholder="Nombre del nuevo cliente" aria-label="Nombre del nuevo cliente" maxlength="80" />
		<button class="btn btn-primary" disabled={!name.trim()} title={name.trim() ? undefined : 'Escribe el nombre del cliente'}><Plus size={16} /> Añadir</button>
	</form>
	{#if error || db.error}<div class="notice notice-danger" role="alert"><CircleAlert size={16} /><p>{error || db.error}</p></div>{/if}

	{#if db.clients.length}
		<ul class="card list">
			{#each db.clients as c (c.id)}
				<li class="row">
					<span class="ic" aria-hidden="true"><Building2 size={16} /></span>
					<div class="info">
						<strong>{c.name}</strong>
						<span class="faint num">{devicesOf(c)} {devicesOf(c) === 1 ? 'equipo' : 'equipos'} · {reposOf(c)} {reposOf(c) === 1 ? 'repositorio' : 'repositorios'}</span>
					</div>
					<div class="acts">
						<a class="icon-btn" href="/informes?cliente={encodeURIComponent(c.id)}" title="Informe mensual" aria-label="Informe mensual de {c.name}"
							><FileText size={16} /></a
						>
						<button class="icon-btn" title="Cambiar nombre" aria-label="Cambiar nombre de {c.name}" onclick={() => (dialog = { kind: 'rename', client: c })}
							><Pencil size={16} /></button
						>
						<button class="icon-btn del" title="Eliminar" aria-label="Eliminar {c.name}" onclick={() => (dialog = { kind: 'remove', client: c })}
							><Trash2 size={16} /></button
						>
					</div>
				</li>
			{/each}
		</ul>
	{:else if db.loaded}
		<div class="empty-state">
			<Building2 size={32} strokeWidth={1.5} />
			<p>Aún no hay clientes. Crea uno arriba y asígnale equipos desde Estado, en el menú «⋯» de cada equipo.</p>
		</div>
	{:else if !db.error}
		<div class="card list" aria-hidden="true">
			{#each { length: 3 } as _}<div class="row"><span class="skel sk-ic"></span><span class="skel sk-line"></span></div>{/each}
		</div>
		<span class="sr-only" role="status">Cargando…</span>
	{/if}
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
		gap: var(--sp-5);
		max-width: 720px;
	}
	.page-head {
		margin-bottom: 0;
	}
	.add {
		display: flex;
		gap: var(--sp-2);
	}
	.list {
		display: flex;
		flex-direction: column;
		margin: 0;
		padding: 0;
		overflow: hidden;
		list-style: none;
	}
	.row {
		display: flex;
		align-items: center;
		gap: var(--sp-3);
		min-height: 52px;
		padding: 10px var(--sp-4);
		transition: background var(--dur-fast) var(--ease);
	}
	.row + .row {
		border-top: 1px solid var(--border);
	}
	li.row:hover {
		background: var(--surface-2);
	}
	.ic {
		display: grid;
		color: var(--text-3);
	}
	.info {
		display: flex;
		flex: 1;
		flex-direction: column;
		min-width: 0;
	}
	.info strong {
		font-weight: 500;
		overflow-wrap: anywhere;
	}
	.info .faint {
		font-size: var(--fs-sm);
		line-height: var(--lh-sm);
	}
	.acts {
		display: flex;
		gap: 2px;
	}
	.del:hover {
		color: var(--bad);
	}
	.sk-ic {
		width: 16px;
		height: 16px;
		border-radius: 999px;
	}
	.sk-line {
		width: 40%;
		height: 14px;
	}
</style>
