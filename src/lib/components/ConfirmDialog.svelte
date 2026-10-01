<script lang="ts">
	// Diálogo pequeño para confirmar una acción o pedir un texto (reemplaza a
	// confirm() y prompt() del navegador, que en el celular se ven fuera de lugar).
	import { untrack } from 'svelte';
	import { CircleAlert, CircleQuestionMark, PenLine, TriangleAlert, X } from '@lucide/svelte';
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

<Modal {onclose} labelledby="{uid}-title" width={440}>
	<form onsubmit={submit}>
		<header class="head">
			<span class="ticon" class:danger aria-hidden="true">
				{#if danger}<TriangleAlert size={18} />{:else if withInput}<PenLine size={18} />{:else}<CircleQuestionMark size={18} />{/if}
			</span>
			<div class="htext">
				<h2 id="{uid}-title">{title}</h2>
				{#if message}<p class="msg">{message}</p>{/if}
			</div>
			<button type="button" class="icon-btn close" aria-label="Cerrar" onclick={onclose}><X size={16} /></button>
		</header>
		{#if withInput}
			<label class="field">
				{#if inputLabel}<span class="field-label">{inputLabel}</span>{/if}
				<input class="input" bind:value={text} {maxlength} use:autofocus />
			</label>
		{/if}
		{#if error}<div class="notice notice-danger" role="alert"><CircleAlert size={16} /><p>{error}</p></div>{/if}
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
		gap: var(--sp-5);
	}
	.head {
		display: flex;
		align-items: flex-start;
		gap: var(--sp-3);
	}
	.ticon {
		display: grid;
		flex: none;
		place-items: center;
		width: 36px;
		height: 36px;
		color: var(--accent-text);
		background: var(--accent-soft);
		border-radius: var(--radius);
	}
	.ticon.danger {
		color: var(--bad);
		background: var(--bad-soft);
	}
	.htext {
		display: flex;
		flex: 1;
		flex-direction: column;
		gap: 2px;
		min-width: 0;
		padding-top: 6px;
	}
	h2 {
		font-size: var(--fs-h2);
		line-height: var(--lh-h2);
		font-weight: 600;
		letter-spacing: -0.01em;
	}
	.msg {
		font-size: var(--fs-sm);
		line-height: var(--lh-sm);
		color: var(--text-2);
	}
	.close {
		margin: -4px -8px 0 0;
	}
	.actions {
		display: flex;
		justify-content: flex-end;
		gap: var(--sp-2);
	}
</style>
