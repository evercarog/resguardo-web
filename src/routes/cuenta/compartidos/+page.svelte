<script lang="ts">
	import { onMount } from 'svelte';
	import { ArrowLeft, CircleAlert, CircleCheck, CircleDashed, CircleX, Clock, LoaderCircle, Share2, TriangleAlert } from '@lucide/svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import InfoTip from '$lib/components/InfoTip.svelte';
	import PlaceIcon from '$lib/components/PlaceIcon.svelte';
	import RelTime from '$lib/components/RelTime.svelte';
	import { friendlyError } from '$lib/data.svelte';
	import { formatDate } from '$lib/format';
	import { supabase } from '$lib/supabase';

	// Destinos que comparten tus equipos y el registro de las peticiones. La web
	// solo ve metadatos y estados: las credenciales viajan cifradas de equipo a
	// equipo y nunca se muestran (ni los sobres).
	type Share = { id: string; device_id: string; device_name: string; kind: string; host: string | null; base: string; name: string; created_at: string };
	type Req = {
		id: string;
		share_id: string;
		status: 'pending' | 'delivered' | 'received' | 'rejected' | 'expired' | 'cancelled';
		reason: string | null;
		not_before: string;
		created_at: string;
		expires_at?: string;
		delivered_at?: string | null;
		received_at?: string | null;
		share_name?: string;
		from_device_name?: string;
		requester_name?: string;
	};

	let shares = $state<Share[]>([]);
	let requests = $state<Req[]>([]);
	let loading = $state(true);
	let error = $state('');
	let now = $state(Date.now());
	let cancelling = $state<Req | null>(null);

	async function load() {
		const [a, b] = await Promise.all([supabase.rpc('shares_list'), supabase.rpc('share_requests_mine')]);
		const e = a.error ?? b.error;
		if (e) error = friendlyError(e.message);
		else {
			error = '';
			shares = (a.data ?? []) as Share[];
			requests = (b.data ?? []) as Req[];
		}
		loading = false;
	}

	onMount(() => {
		load();
		// Mientras haya algo pendiente, se refresca solo.
		const t = setInterval(() => {
			now = Date.now();
			if (requests.some((r) => r.status === 'pending' || r.status === 'delivered')) load();
		}, 20_000);
		return () => clearInterval(t);
	});

	async function cancel(r: Req) {
		const { error: e } = await supabase.rpc('share_cancel', { p_request: r.id });
		if (e) throw new Error(friendlyError(e.message));
		await load();
	}

	/** El estado de una petición en palabras. */
	function stateOf(r: Req) {
		const left = Math.ceil((new Date(r.not_before).getTime() - now) / 60_000);
		switch (r.status) {
			case 'pending':
				return { tone: 'info', icon: Clock, text: left > 0 ? `Pedido · se entrega en ~${left} min` : 'Pedido · se entrega en la próxima vuelta del equipo' };
			case 'delivered':
				return { tone: 'info', icon: LoaderCircle, text: 'Entregado · esperando a que el equipo lo confirme' };
			case 'received':
				return { tone: 'ok', icon: CircleCheck, text: 'Recibido' };
			case 'rejected':
				return { tone: 'warn', icon: TriangleAlert, text: `Rechazado${r.reason ? `: ${r.reason}` : ''}` };
			case 'expired':
				return { tone: 'neutral', icon: CircleDashed, text: 'Caducó sin entregarse' };
			default:
				return { tone: 'neutral', icon: CircleX, text: 'Cancelado' };
		}
	}
</script>

<svelte:head><title>Destinos compartidos · Resguardo</title></svelte:head>

<div class="page">
	<a class="back" href="/cuenta"><ArrowLeft size={14} aria-hidden="true" /> Cuenta</a>
	<header class="page-head">
		<div>
			<h1 class="page-title">Destinos compartidos</h1>
			<p class="page-sub">
				Destinos de la nube o servidores que un equipo tuyo comparte con tus otros equipos. Las claves viajan cifradas de equipo a
				equipo: esta web nunca las ve. Las contraseñas de los repositorios no se comparten nunca.
			</p>
		</div>
	</header>

	{#if error}<div class="notice notice-danger" role="alert"><CircleAlert size={16} /><p>{error}</p></div>{/if}

	<section class="card panel" aria-labelledby="t-shares">
		<div class="panel-head">
			<h2 class="section-title" id="t-shares">Se comparten <span class="count">· {shares.length}</span></h2>
		</div>
		{#if loading}
			<div class="row"><span class="skel sk"></span></div>
		{:else if !shares.length}
			<div class="empty-state small-empty">
				<Share2 size={32} strokeWidth={1.5} />
				<p>Ningún equipo comparte destinos todavía. Se activa en Resguardo, en el equipo, en la página del destino.</p>
			</div>
		{:else}
			<ul class="rows">
				{#each shares as s (s.id)}
					<li class="row">
						<span class="ic" aria-hidden="true"><PlaceIcon kind={s.kind} /></span>
						<div class="what">
							<strong>{s.name}</strong>
							<span class="faint">{s.base}{s.host ? ` · ${s.host}` : ''}</span>
						</div>
						<div class="meta">
							<span>Desde «{s.device_name}»</span>
							<span class="faint">desde el {formatDate(s.created_at)}</span>
						</div>
					</li>
				{/each}
			</ul>
		{/if}
	</section>

	<section class="card panel" aria-labelledby="t-log">
		<div class="panel-head">
			<h2 class="section-title" id="t-log">Peticiones <span class="count">· las tuyas</span></h2>
			<p class="hint">
				Cada petición avisa al momento y no se entrega hasta pasados 5 minutos: si no fuiste tú, cancélala y cambia tu contraseña.
				<InfoTip text="Para revocar del todo un destino ya entregado, deja de compartirlo en Resguardo y rota la clave en la consola del proveedor: lo ya entregado sigue valiendo hasta entonces." />
			</p>
		</div>
		{#if loading}
			<div class="row"><span class="skel sk"></span></div>
		{:else if !requests.length}
			<div class="empty-state small-empty">
				<Clock size={32} strokeWidth={1.5} />
				<p>Todavía no has pedido ningún destino. Se pide desde Resguardo, en el equipo que lo va a usar.</p>
			</div>
		{:else}
			<ul class="rows">
				{#each requests as r (r.id)}
					{@const st = stateOf(r)}
					{@const Icon = st.icon}
					<li class="row">
						<span class="ic tone-{st.tone}" aria-hidden="true"><Icon size={16} /></span>
						<div class="what">
							<strong>«{r.share_name ?? 'Destino'}» para «{r.requester_name ?? 'equipo'}»</strong>
							<span class="state tone-{st.tone}">{st.text}</span>
							<span class="faint">Pedido <RelTime iso={r.created_at} {now} />{r.from_device_name ? ` · lo entrega «${r.from_device_name}»` : ''}</span>
						</div>
						{#if r.status === 'pending'}
							<button class="btn btn-sm" onclick={() => (cancelling = r)}>Cancelar</button>
						{/if}
					</li>
				{/each}
			</ul>
		{/if}
	</section>
</div>

{#if cancelling}
	{@const r = cancelling}
	<ConfirmDialog
		title="¿Cancelar la petición?"
		message="«{r.share_name ?? 'El destino'}» no se entregará a «{r.requester_name ?? 'ese equipo'}». Si no la hiciste tú, cambia también tu contraseña."
		confirmLabel="Cancelar la petición"
		danger
		onconfirm={() => cancel(r)}
		onclose={() => (cancelling = null)}
	/>
{/if}

<style>
	.page {
		display: flex;
		flex-direction: column;
		gap: var(--sp-5);
		max-width: 760px;
	}
	.page-head {
		margin-bottom: 0;
	}
	.page-sub {
		max-width: 64ch;
	}
	.back {
		display: inline-flex;
		align-items: center;
		align-self: flex-start;
		gap: 6px;
		margin-bottom: calc(-1 * var(--sp-3));
		font-size: var(--fs-sm);
		font-weight: 500;
		color: var(--text-2);
	}
	.panel {
		overflow: hidden;
	}
	.panel-head {
		padding: var(--sp-5) var(--sp-5) var(--sp-3);
	}
	.hint {
		margin-top: 2px;
		font-size: var(--fs-sm);
		line-height: var(--lh-sm);
		color: var(--text-3);
	}
	.rows {
		margin: 0;
		padding: 0;
		list-style: none;
	}
	.row {
		display: grid;
		grid-template-columns: 16px minmax(0, 1fr) auto;
		align-items: start;
		gap: var(--sp-3);
		min-height: 44px;
		padding: var(--sp-3) var(--sp-5);
		border-top: 1px solid var(--border);
	}
	.ic {
		display: grid;
		padding-top: 2px;
		color: var(--tone, var(--text-2));
	}
	.what {
		display: flex;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
	}
	.what strong {
		font-weight: 500;
		overflow-wrap: anywhere;
	}
	.what .faint,
	.state {
		font-size: var(--fs-sm);
		line-height: var(--lh-sm);
		overflow-wrap: anywhere;
	}
	.state {
		color: var(--tone);
	}
	.meta {
		display: flex;
		flex-direction: column;
		align-items: flex-end;
		font-size: var(--fs-sm);
		line-height: var(--lh-sm);
		text-align: right;
	}
	.sk {
		grid-column: 1 / -1;
		height: 18px;
	}
	.small-empty {
		padding: var(--sp-8) var(--sp-4);
		border-top: 1px solid var(--border);
	}
	@media (max-width: 600px) {
		.row {
			grid-template-columns: 16px minmax(0, 1fr);
		}
		.meta,
		.row > .btn {
			grid-column: 2;
			align-items: flex-start;
			justify-self: start;
			text-align: left;
		}
	}
</style>
