<script lang="ts">
	// Diálogo pequeño para confirmar una acción o pedir un texto (reemplaza a
	// confirm() y prompt() del navegador, que en el celular se ven fuera de lugar).
	import { untrack } from 'svelte';
	import { CircleAlert } from '@lucide/svelte';
	import Modal from './Modal.svelte';

	interface Props {
		title: string;
		message?: string;
		confirmLabel: string;
		/** Botón de confirmar en rojo (acciones que no se pueden deshacer). */
		danger?: boolean;
		/** Si se indica, muestra un campo de texto con este valor inicial. */
		value?: string;
		inputLabel?: string;
		maxlength?: number;
		/** Recibe el texto (si hay campo). Si lanza un error, se muestra y el diálogo sigue abierto. */
		onconfirm: (value: string) => void | Promise<void>;
		onclose: () => void;
	}
	let { title, message = '', confirmLabel, danger = false, value, inputLabel = '', maxlength = 80, onconfirm, onclose }: Props =
		$props();

	const uid = $props.id();
	// El valor inicial se lee una vez: después manda lo que escribe la persona.
	const withInput = untrack(() => value !== undefined);
	let text = $state(untrack(() => value ?? ''));
	let busy = $state(false);
	let error = $state('');

	const valid = $derived(!withInput || text.trim().length > 0);

	async function submit(e: SubmitEvent) {
		e.preventDefault();
		if (!valid || busy) return;
		busy = true;
		error = '';
		try {
			await onconfirm(text.trim());
			onclose();
		} catch (err) {
			error = err instanceof Error ? err.message : String(err);
		} finally {
			busy = false;
		}
	}

	/** Enfoca el campo (o el botón principal) al abrir y selecciona el texto. */
	function autofocus(node: HTMLElement) {
		node.focus();
		if (node instanceof HTMLInputElement) node.select();
	}
</script>

<Modal {onclose} labelledby="{uid}-title" width={400}>
	<form onsubmit={submit}>
		<h2 id="{uid}-title">{title}</h2>
		{#if message}<p class="msg muted">{message}</p>{/if}
		{#if withInput}
			<label class="field">
				{#if inputLabel}<span class="field-label">{inputLabel}</span>{/if}
				<input class="input" bind:value={text} {maxlength} use:autofocus />
			</label>
		{/if}
		{#if error}<div class="notice notice-danger"><CircleAlert size={16} /><p>{error}</p></div>{/if}
		<div class="actions">
			<button type="button" class="btn btn-ghost" onclick={onclose} disabled={busy}>Cancelar</button>
			{#if withInput}
				<button class="btn btn-primary" disabled={busy || !valid}>{confirmLabel}</button>
			{:else}
				<button class="btn" class:btn-danger={danger} class:btn-primary={!danger} disabled={busy} use:autofocus>{confirmLabel}</button>
			{/if}
		</div>
	</form>
</Modal>

<style>
	form {
		display: flex;
		flex-direction: column;
		gap: 14px;
	}
	h2 {
		font-size: 18px;
		font-weight: 650;
	}
	.msg {
		margin: -6px 0 0;
		line-height: 1.5;
	}
	.actions {
		display: flex;
		justify-content: flex-end;
		gap: 8px;
		margin-top: 4px;
	}
</style>
