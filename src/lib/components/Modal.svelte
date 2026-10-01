<script lang="ts" module>
  /** Modales abiertos, del más antiguo al más reciente. */
  const stack: symbol[] = [];
</script>

<script lang="ts">
  import { onMount, type Snippet } from "svelte";
  import { fade, scale } from "svelte/transition";

  interface Props {
    /** Se llama con Escape o al pulsar fuera. */
    onclose: () => void;
    labelledby: string;
    width?: number;
    children: Snippet;
  }
  let { onclose, labelledby, width = 520, children }: Props = $props();

  const id = Symbol("modal");
  let box: HTMLDivElement;
  const FOCUSABLE = 'a[href], button:not([disabled]), input:not([disabled]), select:not([disabled]), textarea:not([disabled]), [tabindex]:not([tabindex="-1"])';

  // Quién tenía el foco al abrir (antes de que el contenido lo mueva).
  const opener = typeof document !== "undefined" ? (document.activeElement as HTMLElement | null) : null;

  onMount(() => {
    stack.push(id);
    // El foco entra en el diálogo (si el contenido no lo puso ya en un campo
    // o botón) y vuelve a quien lo abrió al cerrarlo.
    if (!box.contains(document.activeElement)) (box.querySelector<HTMLElement>("input, select, textarea") ?? box).focus();
    return () => {
      stack.splice(stack.indexOf(id), 1);
      if (opener?.isConnected) opener.focus();
    };
  });

  function onkeydown(e: KeyboardEvent) {
    if (stack.at(-1) !== id) return;
    if (e.key === "Escape") {
      e.stopPropagation();
      onclose();
    } else if (e.key === "Tab") {
      // El tabulador no sale del diálogo mientras está abierto.
      const items = [...box.querySelectorAll<HTMLElement>(FOCUSABLE)];
      if (!items.length) return;
      const first = items[0];
      const last = items[items.length - 1];
      if (e.shiftKey && (document.activeElement === first || document.activeElement === box)) {
        e.preventDefault();
        last.focus();
      } else if (!e.shiftKey && document.activeElement === last) {
        e.preventDefault();
        first.focus();
      }
    }
  }
</script>

<svelte:window {onkeydown} />

<div class="backdrop" transition:fade|global={{ duration: 150 }} onclick={onclose} role="presentation"></div>

<div
  bind:this={box}
  tabindex="-1"
  class="dialog card"
  style:width="min({width}px, calc(100vw - 32px))"
  role="dialog"
  aria-modal="true"
  aria-labelledby={labelledby}
  transition:scale|global={{ duration: 180, start: 0.96 }}
>
  {@render children()}
</div>

<style>
  .backdrop {
    position: fixed;
    inset: 0;
    z-index: 10;
    background: rgb(8 12 16 / 0.45);
    backdrop-filter: blur(2px);
  }
  .dialog {
    position: fixed;
    z-index: 11;
    top: 50%;
    left: 50%;
    translate: -50% -50%;
    max-height: calc(100vh - 48px);
    max-height: calc(100dvh - 48px);
    overflow: auto;
    padding: 22px 24px 20px;
    box-shadow: var(--shadow-lg);
  }
  .dialog:focus {
    outline: none;
  }
</style>
