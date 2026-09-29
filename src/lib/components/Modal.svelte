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
  onMount(() => {
    stack.push(id);
    return () => stack.splice(stack.indexOf(id), 1);
  });

  function onkeydown(e: KeyboardEvent) {
    if (e.key === "Escape" && stack.at(-1) === id) {
      e.stopPropagation();
      onclose();
    }
  }
</script>

<svelte:window {onkeydown} />

<div class="backdrop" transition:fade|global={{ duration: 150 }} onclick={onclose} role="presentation"></div>

<div
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
</style>
