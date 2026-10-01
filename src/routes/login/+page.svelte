<script lang="ts">
	import { CircleAlert, CircleCheck, LoaderCircle } from '@lucide/svelte';
	import AuthCard from '$lib/components/AuthCard.svelte';
	import { supabase } from '$lib/supabase';

	let email = $state('');
	let password = $state('');
	let busy = $state(false);
	let error = $state('');
	let info = $state('');

	async function submit(e: SubmitEvent) {
		e.preventDefault();
		busy = true;
		error = info = '';
		const { error: err } = await supabase.auth.signInWithPassword({ email: email.trim(), password });
		busy = false;
		// Mensaje genérico: no revelar si el correo existe.
		if (err) error = err.status === 429 ? 'Demasiados intentos. Espera un momento.' : 'Correo o contraseña incorrectos.';
	}

	async function reset() {
		error = info = '';
		if (!email.trim()) {
			error = 'Escribe tu correo para enviarte el enlace.';
			return;
		}
		await supabase.auth.resetPasswordForEmail(email.trim(), { redirectTo: `${location.origin}/mfa` });
		info = 'Si el correo está registrado, te llegará un enlace para cambiar la contraseña.';
	}
</script>

<svelte:head><title>Iniciar sesión · Resguardo</title></svelte:head>

<AuthCard title="Resguardo" subtitle="Inicia sesión para ver el estado de tus copias.">
	<form onsubmit={submit}>
		<label class="field">
			<span class="field-label">Correo</span>
			<input class="input" type="email" autocomplete="username" bind:value={email} required />
		</label>
		<label class="field">
			<span class="field-label">Contraseña</span>
			<input class="input" type="password" autocomplete="current-password" bind:value={password} required />
		</label>
		{#if error}<div class="notice notice-danger" role="alert"><CircleAlert size={16} /><p>{error}</p></div>{/if}
		{#if info}<div class="notice notice-success" role="status"><CircleCheck size={16} /><p>{info}</p></div>{/if}
		<button class="btn btn-primary big" disabled={busy}>
			{#if busy}<span class="spin" style="display:grid"><LoaderCircle size={16} /></span>{/if}
			Entrar
		</button>
		<button type="button" class="link" onclick={reset}>¿Olvidaste la contraseña?</button>
	</form>
</AuthCard>

<style>
	form {
		display: flex;
		flex-direction: column;
		gap: 14px;
	}
	.big {
		height: 42px;
		margin-top: 4px;
	}
	.link {
		align-self: center;
		padding: 4px;
		font: inherit;
		font-size: 13px;
		color: var(--text-2);
		background: none;
		border: none;
		cursor: pointer;
	}
	.link:hover {
		color: var(--accent-soft-text);
	}
</style>
