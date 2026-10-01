<script lang="ts">
	import { onDestroy, onMount } from 'svelte';
	import { CircleAlert, CircleCheck, KeyRound, LoaderCircle, RefreshCw, ShieldCheck } from '@lucide/svelte';
	import { db, friendlyError, loadAll } from '$lib/data.svelte';
	import { supabase } from '$lib/supabase';

	let clientId = $state('');
	let newClient = $state('');
	let code = $state<string | null>(null);
	let expiresAt = $state<number>(0);
	let now = $state(Date.now());
	let busy = $state(false);
	let error = $state('');
	let paired = $state<{ name: string } | null>(null);
	let copied = $state(false);

	const remaining = $derived(Math.max(0, Math.floor((expiresAt - now) / 1000)));
	const pretty = $derived(code ? `${code.slice(0, 4)}-${code.slice(4)}` : '');

	let tick: ReturnType<typeof setInterval>;
	let poll: ReturnType<typeof setInterval> | undefined;
	onMount(() => {
		loadAll();
		tick = setInterval(() => (now = Date.now()), 1000);
	});
	onDestroy(() => {
		clearInterval(tick);
		clearInterval(poll);
	});

	async function generate() {
		busy = true;
		error = '';
		paired = null;
		try {
			let client = clientId || null;
			if (clientId === '__new') {
				const name = newClient.trim();
				if (!name) throw new Error('Escribe el nombre del cliente.');
				const { data, error: e } = await supabase.from('clients').insert({ name }).select('id').single();
				if (e) throw e;
				client = data.id;
				await loadAll();
				clientId = client!;
				newClient = '';
			}
			const { data, error: e } = await supabase.rpc('create_pairing_code', { p_client: client });
			if (e) throw e;
			code = data.code;
			expiresAt = new Date(data.expires_at).getTime();
			watch();
		} catch (e) {
			const msg = e instanceof Error ? e.message : String((e as { message?: string }).message ?? e);
			error = /nombre del cliente/.test(msg) ? msg : friendlyError(`No se pudo generar el código: ${msg}`);
		} finally {
			busy = false;
		}
	}

	/** Comprueba cada pocos segundos si el equipo ya usó el código. */
	function watch() {
		clearInterval(poll);
		poll = setInterval(async () => {
			if (!code || remaining <= 0) return clearInterval(poll);
			const { data } = await supabase.from('pairing_codes').select('device_id, used_at').eq('code', code).maybeSingle();
			if (data?.device_id) {
				clearInterval(poll);
				await loadAll();
				paired = { name: db.devices.find((d) => d.id === data.device_id)?.name ?? 'Equipo' };
				code = null;
			}
		}, 3000);
	}

	async function copy() {
		await navigator.clipboard.writeText(pretty).catch(() => {});
		copied = true;
		setTimeout(() => (copied = false), 1400);
	}

	const mmss = (s: number) => `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
</script>

<svelte:head><title>Vincular equipo · Resguardo</title></svelte:head>

<div class="page">
	<header>
		<h1>Vincular un equipo</h1>
		<p class="faint">El equipo enviará aquí el estado de sus copias automáticas. Nunca envía contraseñas ni nombres de archivos.</p>
	</header>

	<section class="card box">
		{#if paired}
			<div class="done">
				<span class="done-icon"><CircleCheck size={30} /></span>
				<h2>¡{paired.name} está vinculado!</h2>
				<p class="muted">Su estado aparecerá en la página principal en cuanto haga su próximo informe (unos minutos).</p>
				<div class="row">
					<a class="btn btn-primary" href="/">Ver estado</a>
					<button class="btn" onclick={() => (paired = null)}>Vincular otro</button>
				</div>
			</div>
		{:else if code && remaining > 0}
			<div class="code-view">
				<p class="faint">Código de vinculación</p>
				<button class="code mono" onclick={copy} title="Toca para copiarlo" aria-label="Código {pretty}. Toca para copiarlo">{pretty}</button>
				<p class="faint small" aria-live="polite">
					{#if copied}Copiado{:else}Caduca en {mmss(remaining)} · se usa una sola vez{/if}
				</p>
				<div class="waiting" role="status">
					<span class="spin" style="display:grid"><LoaderCircle size={15} aria-hidden="true" /></span> Esperando al equipo…
				</div>
				<ol class="steps">
					<li>En el equipo, abre <strong>Resguardo como administrador</strong>.</li>
					<li>Ve a <strong>Estado → Conectar con la web</strong>.</li>
					<li>Escribe el código <span class="mono">{pretty}</span>.</li>
				</ol>
				<button class="btn btn-ghost btn-sm" onclick={generate}><RefreshCw size={14} /> Generar otro código</button>
			</div>
		{:else}
			<div class="form">
				<label class="field">
					<span class="field-label">Cliente</span>
					<select class="input" bind:value={clientId}>
						<option value="">Sin cliente</option>
						{#each db.clients as c}<option value={c.id}>{c.name}</option>{/each}
						<option value="__new">+ Nuevo cliente…</option>
					</select>
				</label>
				{#if clientId === '__new'}
					<label class="field">
						<span class="field-label">Nombre del cliente</span>
						<input class="input" bind:value={newClient} placeholder="Palmagro SA" maxlength="80" />
					</label>
				{/if}
				{#if code && remaining <= 0}<p class="faint">El código anterior caducó.</p>{/if}
				{#if error}<div class="notice notice-danger" role="alert"><CircleAlert size={16} /><p>{error}</p></div>{/if}
				<button class="btn btn-primary big" onclick={generate} disabled={busy}>
					{#if busy}<span class="spin" style="display:grid"><LoaderCircle size={16} /></span>{:else}<KeyRound size={16} />{/if}
					Generar código
				</button>
			</div>
		{/if}
	</section>

	<p class="faint note">
		<ShieldCheck size={14} aria-hidden="true" /> El código dura 15 minutos y solo sirve una vez. Escríbelo solo en Resguardo, en tu
		equipo: nadie te lo pedirá por teléfono ni por correo.
	</p>
</div>

<style>
	.page {
		display: flex;
		flex-direction: column;
		gap: 18px;
		max-width: 560px;
		margin: 0 auto;
	}
	h1 {
		font-size: 24px;
		font-weight: 700;
	}
	header p {
		margin: 4px 0 0;
		font-size: 13.5px;
		line-height: 1.5;
	}
	.box {
		padding: 24px;
		animation: rise 0.3s cubic-bezier(0.2, 0.8, 0.2, 1) both;
	}
	.form {
		display: flex;
		flex-direction: column;
		gap: 14px;
	}
	.big {
		height: 42px;
	}
	.code-view {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 6px;
		text-align: center;
	}
	.code-view p {
		margin: 0;
	}
	.code {
		margin: 4px 0;
		padding: 10px 18px;
		font-size: clamp(32px, 9vw, 46px);
		font-weight: 700;
		letter-spacing: 0.08em;
		color: var(--accent-soft-text);
		background: var(--accent-soft);
		border: none;
		border-radius: var(--radius-lg);
		cursor: pointer;
		animation: pop 0.35s cubic-bezier(0.2, 0.8, 0.2, 1) both;
	}
	@keyframes pop {
		from {
			transform: scale(0.94);
			opacity: 0;
		}
	}
	.small {
		font-size: 12.5px;
	}
	.waiting {
		display: flex;
		align-items: center;
		gap: 8px;
		margin: 14px 0 4px;
		font-size: 13.5px;
		color: var(--text-2);
	}
	.steps {
		text-align: left;
		margin: 8px 0 12px;
		padding-left: 20px;
		font-size: 13.5px;
		line-height: 1.8;
		color: var(--text-2);
	}
	.done {
		display: flex;
		flex-direction: column;
		align-items: center;
		gap: 8px;
		text-align: center;
	}
	.done-icon {
		display: grid;
		place-items: center;
		width: 60px;
		height: 60px;
		border-radius: 50%;
		color: var(--success);
		background: var(--success-soft);
		animation: pop 0.4s cubic-bezier(0.2, 0.8, 0.2, 1) both;
	}
	.done h2 {
		font-size: 18px;
	}
	.done p {
		margin: 0 0 8px;
	}
	.row {
		display: flex;
		gap: 8px;
	}
	.note {
		display: flex;
		gap: 8px;
		align-items: flex-start;
		margin: 0;
		font-size: 12.5px;
		line-height: 1.5;
	}
	.note :global(svg) {
		flex: none;
		margin-top: 2px;
	}
</style>
