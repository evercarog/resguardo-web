<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { CircleAlert, CircleCheck, CircleQuestionMark, KeyRound, LoaderCircle, LogOut, Plus, ShieldCheck, Smartphone, Trash2, Share2 } from '@lucide/svelte';
	import ConfirmDialog from '$lib/components/ConfirmDialog.svelte';
	import RelTime from '$lib/components/RelTime.svelte';
	import { friendlyError } from '$lib/data.svelte';
	import { formatDate } from '$lib/format';
	import { auth, refreshAuthLevel, signOut } from '$lib/session.svelte';
	import { supabase } from '$lib/supabase';

	// Seguridad de la cuenta: autenticadores (TOTP), contraseña y sesiones.
	// La base de datos exige la verificación en dos pasos (aal2) para todo;
	// aquí solo se gestiona la cuenta de Supabase Auth.

	type Factor = { id: string; friendly_name?: string | null; status: string; created_at: string };

	let email = $state('');
	let lastSignIn = $state<string | null>(null);
	let emailConfirmed = $state(false);
	let factors = $state<Factor[]>([]);
	let loading = $state(true);
	let error = $state('');
	let now = $state(Date.now());

	const verified = $derived(factors.filter((f) => f.status === 'verified'));
	const aal2 = $derived(auth.level === 'aal2');

	// Alta de un autenticador nuevo
	let adding = $state<null | { step: 'name' | 'scan'; name: string; factorId: string; qr: string; secret: string; code: string; busy: boolean; error: string }>(
		null
	);
	// Quitar uno
	let removing = $state<Factor | null>(null);
	// Contraseña
	let current = $state('');
	let next = $state('');
	let repeat = $state('');
	let nonce = $state('');
	let needNonce = $state(false);
	let pwBusy = $state(false);
	let pwError = $state('');
	let pwDone = $state('');
	// Cerrar todas las sesiones
	let confirmAll = $state(false);

	onMount(() => {
		load();
		const t = setInterval(() => (now = Date.now()), 30_000);
		return () => clearInterval(t);
	});

	async function load() {
		loading = true;
		error = '';
		const [{ data: u, error: e1 }, { data: f, error: e2 }] = await Promise.all([supabase.auth.getUser(), supabase.auth.mfa.listFactors()]);
		if (e1 || e2) {
			error = friendlyError((e1 ?? e2)!.message);
			loading = false;
			return;
		}
		email = u.user?.email ?? '';
		lastSignIn = u.user?.last_sign_in_at ?? null;
		emailConfirmed = !!u.user?.email_confirmed_at;
		// Intentos de alta sin terminar: se quitan (no sirven para entrar).
		for (const x of f.all.filter((x) => x.factor_type === 'totp' && x.status === 'unverified')) await supabase.auth.mfa.unenroll({ factorId: x.id });
		factors = f.totp as Factor[];
		loading = false;
	}

	/** Nombre por defecto para el siguiente autenticador. */
	const suggestedName = $derived(verified.length ? 'Celular de respaldo' : 'Celular principal');

	function startAdd() {
		adding = { step: 'name', name: suggestedName, factorId: '', qr: '', secret: '', code: '', busy: false, error: '' };
	}

	async function enroll(e: SubmitEvent) {
		e.preventDefault();
		if (!adding) return;
		const name = adding.name.trim();
		if (!name) return;
		if (factors.some((f) => (f.friendly_name ?? '').toLowerCase() === name.toLowerCase())) {
			adding.error = 'Ya tienes un autenticador con ese nombre. Elige otro.';
			return;
		}
		adding.busy = true;
		adding.error = '';
		const { data, error: err } = await supabase.auth.mfa.enroll({ factorType: 'totp', friendlyName: name });
		adding.busy = false;
		if (err || !data) {
			adding.error = 'No se pudo preparar el autenticador. Inténtalo de nuevo.';
			return;
		}
		adding = { ...adding, step: 'scan', factorId: data.id, qr: data.totp.qr_code, secret: data.totp.secret };
	}

	async function verifyNew(e: SubmitEvent) {
		e.preventDefault();
		if (!adding) return;
		adding.busy = true;
		adding.error = '';
		const { error: err } = await supabase.auth.mfa.challengeAndVerify({ factorId: adding.factorId, code: adding.code.replace(/\s/g, '') });
		adding.busy = false;
		if (err) {
			adding.error = 'Código incorrecto o caducado. Prueba con el siguiente que muestre la app.';
			adding.code = '';
			return;
		}
		adding = null;
		await refreshAuthLevel();
		await load();
	}

	async function cancelAdd() {
		const id = adding?.factorId;
		adding = null;
		if (id) await supabase.auth.mfa.unenroll({ factorId: id });
	}

	async function remove(f: Factor) {
		if (!aal2) throw new Error('Vuelve a verificar tu identidad (verificación en dos pasos) para quitar un autenticador.');
		if (f.status === 'verified' && verified.length < 2) throw new Error('No puedes quitar tu único autenticador: te quedarías sin poder entrar.');
		const { error: err } = await supabase.auth.mfa.unenroll({ factorId: f.id });
		if (err) throw new Error('No se pudo quitar. Inténtalo de nuevo.');
		await refreshAuthLevel();
		await load();
	}

	/** Fuerza orientativa de la contraseña nueva. */
	const strength = $derived.by(() => {
		const p = next;
		if (!p) return null;
		const kinds = [/[a-záéíóúñ]/, /[A-ZÁÉÍÓÚÑ]/, /\d/, /[^A-Za-z0-9áéíóúñÁÉÍÓÚÑ]/].filter((r) => r.test(p)).length;
		if (p.length < 12) return { level: 0, text: `Muy corta: faltan ${12 - p.length} caracteres.` };
		if (p.length >= 20 || (p.length >= 16 && kinds >= 2)) return { level: 3, text: 'Buena.' };
		if (kinds >= 3) return { level: 2, text: 'Aceptable. Más larga sería mejor.' };
		return { level: 1, text: 'Floja: alárgala o mezcla palabras, números y signos.' };
	});

	async function changePassword(e: SubmitEvent) {
		e.preventDefault();
		pwError = pwDone = '';
		if (next.length < 12) {
			pwError = 'Usa al menos 12 caracteres.';
			return;
		}
		if (next !== repeat) {
			pwError = 'Las dos contraseñas nuevas no coinciden.';
			return;
		}
		if (next === current) {
			pwError = 'La contraseña nueva tiene que ser distinta de la actual.';
			return;
		}
		pwBusy = true;
		const { error: err } = await supabase.auth.updateUser({
			password: next,
			// Si el servidor pide la contraseña actual o un código enviado al correo, aquí van.
			current_password: current || undefined,
			nonce: needNonce ? nonce.trim() : undefined
		});
		pwBusy = false;
		if (err) {
			const code = (err as { code?: string }).code ?? '';
			if (code === 'reauthentication_needed' || code === 'reauthentication_not_valid') {
				// El servidor pide confirmar con un código enviado al correo.
				if (!needNonce || code === 'reauthentication_not_valid') {
					await supabase.auth.reauthenticate();
					needNonce = true;
				}
				pwError =
					code === 'reauthentication_not_valid'
						? 'El código no es válido o caducó. Te enviamos uno nuevo al correo.'
						: `Por seguridad, te enviamos un código a ${email}. Escríbelo abajo y vuelve a guardar.`;
				return;
			}
			if (code === 'same_password') pwError = 'La contraseña nueva tiene que ser distinta de la actual.';
			else if (code === 'weak_password') pwError = 'La contraseña es demasiado débil o aparece en filtraciones conocidas. Elige otra.';
			else if (/current/i.test(code) || /current password/i.test(err.message)) pwError = 'La contraseña actual no es correcta.';
			else if (code === 'insufficient_aal') pwError = 'Vuelve a verificar tu identidad (verificación en dos pasos) e inténtalo de nuevo.';
			else pwError = friendlyError('No se pudo cambiar la contraseña. Inténtalo de nuevo.');
			return;
		}
		current = next = repeat = nonce = '';
		needNonce = false;
		pwDone = 'Contraseña cambiada. Úsala la próxima vez que entres.';
	}

	async function signOutEverywhere() {
		await signOut();
		goto('/login');
	}
</script>

<svelte:head><title>Seguridad de la cuenta · Resguardo</title></svelte:head>

<div class="page">
	<header class="page-head">
		<div>
			<h1 class="page-title">Seguridad de la cuenta</h1>
			<p class="page-sub">Autenticadores, contraseña y sesiones. Solo tú ves esta página.</p>
		</div>
	</header>

	{#if error}<div class="notice notice-danger" role="alert"><CircleAlert size={16} /><p>{error}</p></div>{/if}

	{#if loading}
		<div class="card box" aria-hidden="true"><span class="skel sk"></span><span class="skel sk short"></span></div>
		<span class="sr-only" role="status">Cargando…</span>
	{:else}
		<!-- Cuenta -->
		<section class="card box" aria-labelledby="t-cuenta">
			<h2 id="t-cuenta">Cuenta</h2>
			<dl class="facts">
				<div><dt>Correo</dt><dd class="selectable">{email}</dd></div>
				<div>
					<dt>Último inicio de sesión</dt>
					<dd>{#if lastSignIn}<RelTime iso={lastSignIn} {now} /> <span class="faint">· {formatDate(lastSignIn)}</span>{:else}—{/if}</dd>
				</div>
			</dl>
		</section>

		<!-- Lista de comprobación -->
		<section class="card box" aria-labelledby="t-check">
			<h2 id="t-check">Lista de comprobación</h2>
			<ul class="check">
				<li class:ok={verified.length >= 2}>
					{#if verified.length >= 2}<CircleCheck size={17} aria-hidden="true" />{:else}<CircleAlert size={17} aria-hidden="true" />{/if}
					<span>
						<strong>Segundo autenticador</strong><span class="sr-only">: {verified.length >= 2 ? 'hecho' : 'pendiente'}</span>
						<span class="faint">
							{verified.length >= 2
								? `Tienes ${verified.length} autenticadores. Si pierdes el celular, podrás entrar con el otro.`
								: 'Pendiente. Si pierdes el celular, sin un segundo autenticador no podrás entrar.'}
						</span>
					</span>
				</li>
				<li class:ok={emailConfirmed}>
					{#if emailConfirmed}<CircleCheck size={17} aria-hidden="true" />{:else}<CircleAlert size={17} aria-hidden="true" />{/if}
					<span>
						<strong>Correo de recuperación confirmado</strong><span class="sr-only">: {emailConfirmed ? 'hecho' : 'pendiente'}</span>
						<span class="faint">{emailConfirmed ? `Los enlaces para cambiar la contraseña llegan a ${email}.` : 'Confirma tu correo para poder recuperar la contraseña.'}</span>
					</span>
				</li>
				<li class="note">
					<CircleQuestionMark size={17} aria-hidden="true" />
					<span>
						<strong>Registro de cuentas nuevas cerrado</strong>
						<span class="faint">Recordatorio: en Supabase (Authentication → Sign In / Providers) desactiva «Allow new users to sign up». Desde aquí no se puede comprobar.</span>
					</span>
				</li>
			</ul>
		</section>

		<!-- Autenticadores -->
		<section class="card box" aria-labelledby="t-mfa">
			<div class="head">
				<h2 id="t-mfa"><ShieldCheck size={17} aria-hidden="true" /> Autenticadores</h2>
				{#if !adding}
					<button class="btn btn-sm" onclick={startAdd} disabled={!aal2}><Plus size={14} aria-hidden="true" /> Añadir otro</button>
				{/if}
			</div>
			<p class="faint lead">
				Apps que generan el código de 6 dígitos para entrar. Registra al menos dos (por ejemplo, tu celular y otro de respaldo): si
				pierdes el celular, podrás entrar con el otro.
			</p>

			<ul class="factors">
				{#each verified as f (f.id)}
					<li>
						<span class="ic"><Smartphone size={16} aria-hidden="true" /></span>
						<span class="info">
							<strong>{f.friendly_name || 'Autenticador'}</strong>
							<span class="faint">Añadido el {formatDate(f.created_at)}</span>
						</span>
						<button
							class="icon-btn del"
							title={verified.length < 2 ? 'Es tu único autenticador: no se puede quitar' : 'Quitar'}
							aria-label="Quitar {f.friendly_name || 'autenticador'}"
							disabled={verified.length < 2 || !aal2}
							onclick={() => (removing = f)}><Trash2 size={15} /></button
						>
					</li>
				{/each}
			</ul>
			{#if verified.length < 2}
				<p class="faint small">Tu único autenticador no se puede quitar: te quedarías sin poder entrar.</p>
			{/if}

			{#if adding}
				<div class="add">
					{#if adding.step === 'name'}
						<form onsubmit={enroll}>
							<label class="field">
								<span class="field-label">Nombre del autenticador</span>
								<input class="input" bind:value={adding.name} maxlength="40" required />
								<span class="field-hint">Para reconocerlo en esta lista: «Celular de respaldo», «iPad de la oficina»…</span>
							</label>
							{#if adding.error}<div class="notice notice-danger" role="alert"><CircleAlert size={16} /><p>{adding.error}</p></div>{/if}
							<div class="row">
								<button class="btn btn-ghost" type="button" onclick={() => (adding = null)}>Cancelar</button>
								<button class="btn btn-primary" disabled={adding.busy}>
									{#if adding.busy}<span class="spin" style="display:grid"><LoaderCircle size={15} /></span>{/if}
									Continuar
								</button>
							</div>
						</form>
					{:else}
						<form onsubmit={verifyNew}>
							<p class="faint">Escanea el código con la app de autenticación del otro dispositivo y escribe el código que muestre.</p>
							<div class="qr"><img src={adding.qr} alt="Código QR para la app de autenticación" /></div>
							<details class="manual">
								<summary>¿No puedes escanearlo? Escribe la clave a mano</summary>
								<p class="faint">No la compartas con nadie: quien la tenga puede generar tus códigos.</p>
								<code class="selectable">{adding.secret}</code>
							</details>
							<input
								class="input code"
								inputmode="numeric"
								autocomplete="one-time-code"
								maxlength="7"
								placeholder="000000"
								aria-label="Código de 6 dígitos del nuevo autenticador"
								bind:value={adding.code}
								required
							/>
							{#if adding.error}<div class="notice notice-danger" role="alert"><CircleAlert size={16} /><p>{adding.error}</p></div>{/if}
							<div class="row">
								<button class="btn btn-ghost" type="button" onclick={cancelAdd}>Cancelar</button>
								<button class="btn btn-primary" disabled={adding.busy || adding.code.replace(/\s/g, '').length < 6}>
									{#if adding.busy}<span class="spin" style="display:grid"><LoaderCircle size={15} /></span>{:else}<ShieldCheck size={15} />{/if}
									Activar
								</button>
							</div>
						</form>
					{/if}
				</div>
			{/if}
		</section>

		<!-- Contraseña -->
		<section class="card box" aria-labelledby="t-pass">
			<h2 id="t-pass"><KeyRound size={17} aria-hidden="true" /> Contraseña</h2>
			<form class="form" onsubmit={changePassword}>
				<label class="field">
					<span class="field-label">Contraseña actual</span>
					<input class="input" type="password" autocomplete="current-password" bind:value={current} required />
				</label>
				<label class="field">
					<span class="field-label">Contraseña nueva</span>
					<input class="input" type="password" autocomplete="new-password" minlength="12" bind:value={next} required aria-describedby="pw-hint" />
					<span class="field-hint" id="pw-hint">
						Al menos 12 caracteres. Mejor una frase larga (por ejemplo, cuatro palabras al azar) que no uses en ningún otro sitio.
					</span>
					{#if strength}
						<span class="meter" aria-live="polite">
							<span class="bars" aria-hidden="true">
								{#each [1, 2, 3] as n}<span class="bar" class:on={strength.level >= n} data-l={strength.level}></span>{/each}
							</span>
							<span class="faint small">{strength.text}</span>
						</span>
					{/if}
				</label>
				<label class="field">
					<span class="field-label">Repite la contraseña nueva</span>
					<input class="input" type="password" autocomplete="new-password" bind:value={repeat} required />
				</label>
				{#if needNonce}
					<label class="field">
						<span class="field-label">Código enviado a tu correo</span>
						<input class="input" inputmode="numeric" autocomplete="one-time-code" bind:value={nonce} required />
					</label>
				{/if}
				{#if pwError}<div class="notice notice-danger" role="alert"><CircleAlert size={16} /><p>{pwError}</p></div>{/if}
				{#if pwDone}<div class="notice notice-success" role="status"><CircleCheck size={16} /><p>{pwDone}</p></div>{/if}
				<div class="row">
					<button class="btn btn-primary" disabled={pwBusy || !aal2}>
						{#if pwBusy}<span class="spin" style="display:grid"><LoaderCircle size={15} /></span>{/if}
						Cambiar contraseña
					</button>
				</div>
			</form>
		</section>

		<!-- Destinos compartidos -->
		<section class="card box" aria-labelledby="t-shr">
			<h2 id="t-shr"><Share2 size={17} aria-hidden="true" /> Destinos compartidos</h2>
			<p class="faint lead">
				Los destinos que tus equipos comparten entre sí y tus peticiones: cuándo se entregan y quién las recibió. Si alguna no la hiciste
				tú, cancélala desde ahí.
			</p>
			<div class="row start"><a class="btn" href="/cuenta/compartidos">Ver destinos compartidos</a></div>
		</section>

		<!-- Sesiones -->
		<section class="card box" aria-labelledby="t-ses">
			<h2 id="t-ses"><LogOut size={17} aria-hidden="true" /> Sesiones</h2>
			<p class="faint lead">
				Si dejaste la sesión abierta en un equipo que no es tuyo o perdiste un dispositivo, ciérrala en todas partes. Tendrás que volver a
				entrar con la contraseña y el código.
			</p>
			<div class="row start">
				<button class="btn btn-danger" onclick={() => (confirmAll = true)}><LogOut size={15} aria-hidden="true" /> Cerrar sesión en todos los dispositivos</button>
			</div>
		</section>
	{/if}
</div>

{#if removing}
	{@const f = removing}
	<ConfirmDialog
		title="¿Quitar «{f.friendly_name || 'Autenticador'}»?"
		message="Ya no podrás entrar con los códigos de esa app. Te queda{verified.length - 1 === 1 ? '' : 'n'} {verified.length - 1} autenticador{verified.length - 1 === 1 ? '' : 'es'}."
		confirmLabel="Quitar"
		danger
		onconfirm={() => remove(f)}
		onclose={() => (removing = null)}
	/>
{/if}

{#if confirmAll}
	<ConfirmDialog
		title="¿Cerrar sesión en todos los dispositivos?"
		message="Se cerrará también en este. Para volver a entrar necesitarás tu contraseña y el código de verificación."
		confirmLabel="Cerrar todas"
		danger
		onconfirm={signOutEverywhere}
		onclose={() => (confirmAll = false)}
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
	.box {
		display: flex;
		flex-direction: column;
		gap: var(--sp-3);
		padding: var(--sp-5);
		animation: rise var(--dur-slow) var(--ease-out) both;
	}
	h2 {
		display: flex;
		align-items: center;
		gap: var(--sp-2);
		font-size: var(--fs-h2);
		line-height: var(--lh-h2);
		font-weight: 600;
		letter-spacing: -0.01em;
	}
	.head {
		display: flex;
		align-items: center;
		justify-content: space-between;
		gap: 10px;
	}
	.lead {
		margin: 0;
		font-size: var(--fs-sm);
		line-height: var(--lh-sm);
	}
	.small {
		font-size: var(--fs-sm);
	}
	p.small {
		margin: 0;
	}
	.facts {
		display: grid;
		grid-template-columns: repeat(auto-fit, minmax(min(100%, 220px), 1fr));
		gap: 12px;
		margin: 0;
	}
	.facts dt {
		font-size: var(--fs-xs);
		color: var(--text-3);
	}
	.facts dd {
		margin: 2px 0 0;
		font-weight: 600;
		overflow-wrap: anywhere;
	}
	.facts dd .faint {
		font-weight: 400;
	}
	.check,
	.factors {
		display: flex;
		flex-direction: column;
		gap: 6px;
		margin: 0;
		padding: 0;
		list-style: none;
	}
	.check li {
		display: flex;
		align-items: flex-start;
		gap: 10px;
		padding: var(--sp-3);
		font-size: var(--fs-sm);
		line-height: var(--lh-sm);
		color: var(--warn);
		background: var(--surface-2);
		border-radius: var(--radius);
	}
	.check li :global(svg) {
		flex: none;
		margin-top: 1px;
	}
	.check li.ok {
		color: var(--ok);
	}
	.check li.note {
		color: var(--text-3);
	}
	.check li > span {
		display: flex;
		flex-direction: column;
	}
	.check strong {
		color: var(--text-1);
		font-weight: 500;
	}
	.factors li {
		display: flex;
		align-items: center;
		gap: 12px;
		padding: 10px var(--sp-3);
		background: var(--surface-2);
		border-radius: var(--radius);
	}
	.ic {
		display: grid;
		place-items: center;
		width: 32px;
		height: 32px;
		flex: none;
		border-radius: 9px;
		color: var(--accent-text);
		background: var(--accent-soft);
	}
	.info {
		display: flex;
		flex: 1;
		flex-direction: column;
		min-width: 0;
	}
	.info .faint {
		font-size: var(--fs-sm);
	}
	.del:hover:not(:disabled) {
		color: var(--bad);
	}
	.del:disabled {
		opacity: 0.4;
		cursor: not-allowed;
	}
	.add {
		padding: 14px;
		background: var(--surface-2);
		border: 1px solid var(--border);
		border-radius: var(--radius);
	}
	.add form,
	.form {
		display: flex;
		flex-direction: column;
		gap: 12px;
	}
	.add p {
		margin: 0;
		font-size: var(--fs-sm);
	}
	.row {
		display: flex;
		justify-content: flex-end;
		gap: 8px;
		flex-wrap: wrap;
	}
	.row.start {
		justify-content: flex-start;
	}
	.qr {
		display: grid;
		place-items: center;
		align-self: center;
		padding: 10px;
		width: 200px;
		background: #fff;
		border-radius: var(--radius);
	}
	.qr img {
		width: 180px;
		height: 180px;
	}
	.manual {
		font-size: var(--fs-sm);
	}
	.manual summary {
		cursor: pointer;
		color: var(--text-2);
	}
	.manual code {
		display: block;
		margin-top: 6px;
		padding: 8px;
		word-break: break-all;
		background: var(--surface);
		border-radius: var(--radius-sm);
	}
	.code {
		height: 48px;
		font-family: var(--mono);
		font-size: var(--fs-title);
		letter-spacing: 0.35em;
		text-align: center;
	}
	.meter {
		display: flex;
		align-items: center;
		gap: 10px;
	}
	.bars {
		display: grid;
		grid-template-columns: repeat(3, 28px);
		gap: 4px;
	}
	.bar {
		height: 5px;
		border-radius: 999px;
		background: var(--surface-3);
	}
	.bar.on[data-l='1'] {
		background: var(--bad);
	}
	.bar.on[data-l='2'] {
		background: var(--warn);
	}
	.bar.on[data-l='3'] {
		background: var(--ok);
	}
	.sk {
		height: 18px;
		width: 60%;
	}
	.sk.short {
		width: 35%;
	}
</style>
