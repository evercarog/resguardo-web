<script lang="ts">
	import { onMount } from 'svelte';
	import { goto } from '$app/navigation';
	import { CircleAlert, LoaderCircle, LogOut, ShieldCheck } from '@lucide/svelte';
	import AuthCard from '$lib/components/AuthCard.svelte';
	import { refreshAuthLevel, signOut } from '$lib/session.svelte';
	import { supabase } from '$lib/supabase';

	// Verificación en dos pasos (TOTP): obligatoria. La base de datos no
	// muestra ningún dato sin ella.
	let mode = $state<'loading' | 'enroll' | 'verify' | 'newpass'>('loading');
	let factorId = $state('');
	let qr = $state('');
	let secret = $state('');
	let code = $state('');
	let newPassword = $state('');
	let busy = $state(false);
	let error = $state('');

	onMount(async () => {
		// Llegó desde el enlace de "olvidé la contraseña".
		if (location.hash.includes('type=recovery')) {
			mode = 'newpass';
			return;
		}
		await prepare();
	});

	async function prepare() {
		const { data, error: err } = await supabase.auth.mfa.listFactors();
		if (err) {
			error = err.message;
			return;
		}
		const verified = data.totp.find((f) => f.status === 'verified');
		if (verified) {
			factorId = verified.id;
			mode = 'verify';
			return;
		}
		// Quitar intentos anteriores sin terminar y empezar uno nuevo.
		for (const f of data.all.filter((f) => f.status === 'unverified')) await supabase.auth.mfa.unenroll({ factorId: f.id });
		const { data: enrolled, error: e2 } = await supabase.auth.mfa.enroll({ factorType: 'totp', friendlyName: 'Resguardo' });
		if (e2 || !enrolled) {
			error = e2?.message ?? 'No se pudo preparar la verificación.';
			return;
		}
		factorId = enrolled.id;
		qr = enrolled.totp.qr_code;
		secret = enrolled.totp.secret;
		mode = 'enroll';
	}

	async function verify(e: SubmitEvent) {
		e.preventDefault();
		busy = true;
		error = '';
		const { error: err } = await supabase.auth.mfa.challengeAndVerify({ factorId, code: code.replace(/\s/g, '') });
		busy = false;
		if (err) {
			error = 'Código incorrecto o caducado. Prueba con el siguiente.';
			code = '';
			return;
		}
		await refreshAuthLevel();
		goto('/', { replaceState: true });
	}

	async function savePassword(e: SubmitEvent) {
		e.preventDefault();
		if (newPassword.length < 12) {
			error = 'Usa al menos 12 caracteres.';
			return;
		}
		busy = true;
		const { error: err } = await supabase.auth.updateUser({ password: newPassword });
		busy = false;
		if (err) {
			error = err.message;
			return;
		}
		history.replaceState(null, '', '/mfa');
		mode = 'loading';
		await prepare();
	}

	async function leave() {
		await signOut();
		goto('/login');
	}
</script>

<svelte:head><title>Verificación · Resguardo</title></svelte:head>

<AuthCard
	title={mode === 'enroll' ? 'Protege tu cuenta' : mode === 'newpass' ? 'Nueva contraseña' : 'Verificación en dos pasos'}
	subtitle={mode === 'enroll'
		? 'Escanea el código con una app de autenticación (Google Authenticator, Microsoft Authenticator, 1Password…).'
		: mode === 'verify'
			? 'Escribe el código de 6 dígitos de tu app de autenticación.'
			: mode === 'newpass'
				? 'Elige una contraseña nueva para tu cuenta.'
				: ''}
>
	{#if mode === 'loading'}
		<div class="center"><span class="spin" style="display:grid"><LoaderCircle size={22} /></span></div>
	{:else if mode === 'newpass'}
		<form onsubmit={savePassword}>
			<input class="input" type="password" autocomplete="new-password" bind:value={newPassword} placeholder="Al menos 12 caracteres" required />
			{#if error}<div class="notice notice-danger"><CircleAlert size={16} /><p>{error}</p></div>{/if}
			<button class="btn btn-primary big" disabled={busy}>Guardar contraseña</button>
		</form>
	{:else}
		{#if mode === 'enroll'}
			<div class="qr"><img src={qr} alt="Código QR para la app de autenticación" /></div>
			<details class="manual">
				<summary>¿No puedes escanearlo?</summary>
				<p class="faint">Escribe esta clave en tu app:</p>
				<code class="selectable">{secret}</code>
			</details>
		{/if}
		<form onsubmit={verify}>
			<input
				class="input code"
				inputmode="numeric"
				autocomplete="one-time-code"
				maxlength="7"
				placeholder="000000"
				bind:value={code}
				required
			/>
			{#if error}<div class="notice notice-danger"><CircleAlert size={16} /><p>{error}</p></div>{/if}
			<button class="btn btn-primary big" disabled={busy || code.replace(/\s/g, '').length < 6}>
				{#if busy}<span class="spin" style="display:grid"><LoaderCircle size={16} /></span>{:else}<ShieldCheck size={16} />{/if}
				{mode === 'enroll' ? 'Activar y entrar' : 'Verificar'}
			</button>
		</form>
	{/if}
	<button class="link" onclick={leave}><LogOut size={13} /> Salir</button>
</AuthCard>

<style>
	form {
		display: flex;
		flex-direction: column;
		gap: 12px;
	}
	.center {
		display: grid;
		place-items: center;
		padding: 20px;
		color: var(--text-3);
	}
	.qr {
		display: grid;
		place-items: center;
		margin: -6px auto 14px;
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
		margin-bottom: 14px;
		font-size: 13px;
		text-align: center;
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
		background: var(--surface-2);
		border-radius: var(--radius-sm);
	}
	.code {
		height: 52px;
		font-family: var(--mono);
		font-size: 26px;
		letter-spacing: 0.35em;
		text-align: center;
	}
	.big {
		height: 42px;
	}
	.link {
		display: flex;
		align-items: center;
		gap: 6px;
		margin: 16px auto 0;
		padding: 4px;
		font: inherit;
		font-size: 13px;
		color: var(--text-3);
		background: none;
		border: none;
		cursor: pointer;
	}
</style>
