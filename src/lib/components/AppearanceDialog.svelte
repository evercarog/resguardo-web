<script lang="ts">
  import { Check, Palette, X } from "@lucide/svelte";
  import { ACCENTS, THEMES, appearance, setAccent, setTheme } from "$lib/settings.svelte";
  import Modal from "./Modal.svelte";

  let { onclose }: { onclose: () => void } = $props();

  /** Colores de las miniaturas de cada modo: [fondo, barra lateral, tarjeta, texto]. */
  const PREVIEW = {
    light: ["#f4f5f7", "#ffffff", "#ffffff", "#c9ced6"],
    dark: ["#0d1014", "#151a1f", "#1a2027", "#3a4450"],
    black: ["#000000", "#0b0b0c", "#111113", "#2e2e33"],
  } as const;
  const current = $derived(ACCENTS.find((a) => a.id === appearance.accent)!);
</script>

{#snippet mini(mode: "light" | "dark" | "black", accent: string)}
  {@const [bg, side, card, line] = PREVIEW[mode]}
  <svg viewBox="0 0 120 76" aria-hidden="true">
    <rect width="120" height="76" fill={bg} />
    <rect width="34" height="76" fill={side} />
    <rect x="6" y="8" width="22" height="7" rx="2" fill={accent} />
    <rect x="6" y="20" width="18" height="4" rx="2" fill={line} />
    <rect x="6" y="28" width="20" height="4" rx="2" fill={line} />
    <rect x="42" y="8" width="70" height="26" rx="4" fill={card} stroke={line} stroke-opacity="0.5" />
    <rect x="48" y="14" width="30" height="4" rx="2" fill={line} />
    <rect x="92" y="14" width="14" height="7" rx="2" fill={accent} />
    <rect x="48" y="24" width="56" height="4" rx="2" fill={accent} fill-opacity="0.5" />
    <rect x="42" y="40" width="70" height="28" rx="4" fill={card} stroke={line} stroke-opacity="0.5" />
    <rect x="48" y="47" width="44" height="4" rx="2" fill={line} />
    <rect x="48" y="56" width="36" height="4" rx="2" fill={line} />
  </svg>
{/snippet}

<Modal {onclose} labelledby="appearance-title" width={560}>
  <header>
    <div class="title">
      <span class="ticon"><Palette size={19} /></span>
      <h2 id="appearance-title">Apariencia</h2>
    </div>
    <button class="icon-btn" title="Cerrar" aria-label="Cerrar" onclick={onclose}><X size={17} /></button>
  </header>

  <section>
    <h3>Modo</h3>
    <div class="themes" role="radiogroup" aria-label="Modo">
      {#each THEMES as t}
        <button class="theme" class:on={appearance.theme === t.id} role="radio" aria-checked={appearance.theme === t.id} onclick={() => setTheme(t.id)}>
          <span class="thumb">
            {#if t.id === "system"}
              <span class="split">
                <span class="half">{@render mini("light", current.light)}</span>
                <span class="half right">{@render mini("dark", current.dark)}</span>
              </span>
            {:else}
              {@render mini(t.id, t.id === "light" ? current.light : current.dark)}
            {/if}
          </span>
          <span class="theme-label">
            {#if appearance.theme === t.id}<Check size={13} />{/if}
            {t.label}
          </span>
        </button>
      {/each}
    </div>
    <p class="faint hint">«Sistema» sigue el modo claro u oscuro de tu dispositivo automáticamente.</p>
  </section>

  <section>
    <h3>Color de acento</h3>
    <div class="accents" role="radiogroup" aria-label="Color de acento">
      {#each ACCENTS as a}
        <button
          class="swatch"
          class:on={appearance.accent === a.id}
          role="radio"
          aria-checked={appearance.accent === a.id}
          title={a.label}
          onclick={() => setAccent(a.id)}
          style:--l={a.light}
          style:--d={a.dark}
        >
          <span class="dot">{#if appearance.accent === a.id}<Check size={14} strokeWidth={3} />{/if}</span>
        </button>
      {/each}
    </div>
    <p class="faint hint">{current.label}</p>
  </section>

  <footer>
    <button class="btn btn-primary" onclick={onclose}>Listo</button>
  </footer>
</Modal>

<style>
  header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 18px;
  }
  .title {
    display: flex;
    align-items: center;
    gap: 12px;
  }
  .ticon {
    display: grid;
    place-items: center;
    width: 38px;
    height: 38px;
    border-radius: 11px;
    color: var(--accent-soft-text);
    background: var(--accent-soft);
  }
  h2 {
    font-size: 18px;
    font-weight: 700;
  }
  section + section {
    margin-top: 22px;
  }
  h3 {
    margin-bottom: 10px;
    font-size: 13px;
    font-weight: 650;
    color: var(--text-2);
  }
  .themes {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 10px;
  }
  .theme {
    display: flex;
    flex-direction: column;
    gap: 7px;
    padding: 0;
    font: inherit;
    color: var(--text-2);
    background: none;
    border: none;
    cursor: pointer;
  }
  .thumb {
    display: block;
    overflow: hidden;
    border-radius: var(--radius);
    border: 2px solid var(--border);
    transition:
      border-color 0.15s,
      box-shadow 0.15s;
  }
  .thumb :global(svg) {
    display: block;
    width: 100%;
    height: auto;
  }
  .theme:hover .thumb {
    border-color: var(--border-strong);
  }
  .theme.on .thumb {
    border-color: var(--accent);
    box-shadow: 0 0 0 3px var(--accent-soft);
  }
  .split {
    position: relative;
    display: block;
  }
  .half.right {
    position: absolute;
    inset: 0;
    clip-path: polygon(55% 0, 100% 0, 100% 100%, 35% 100%);
  }
  .theme-label {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 4px;
    font-size: 13px;
    font-weight: 550;
  }
  .theme.on .theme-label {
    color: var(--text);
  }
  .hint {
    margin: 8px 0 0;
    font-size: 12.5px;
  }
  .accents {
    display: flex;
    flex-wrap: wrap;
    gap: 10px;
  }
  .swatch {
    display: grid;
    place-items: center;
    width: 40px;
    height: 40px;
    padding: 0;
    background: none;
    border: 2px solid transparent;
    border-radius: 50%;
    cursor: pointer;
    transition: border-color 0.15s;
  }
  .swatch.on {
    border-color: var(--text-3);
  }
  .dot {
    display: grid;
    place-items: center;
    width: 30px;
    height: 30px;
    border-radius: 50%;
    color: #fff;
    background: linear-gradient(135deg, var(--l) 50%, var(--d) 50%);
    box-shadow: inset 0 0 0 1px rgb(0 0 0 / 0.1);
  }
  footer {
    display: flex;
    justify-content: flex-end;
    margin-top: 24px;
  }
</style>
