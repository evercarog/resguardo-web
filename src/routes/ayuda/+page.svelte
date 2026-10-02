<script lang="ts">
	import { onMount } from 'svelte';
	import { GLOSSARY, GLOSSARY_GROUPS, type GlossaryEntry } from '$lib/glossary';

	// «Qué significa cada cosa»: el glosario entero, por grupos (los mismos
	// textos que los «?» de la web y de la app de escritorio).
	const groups = (Object.keys(GLOSSARY_GROUPS) as GlossaryEntry['group'][]).map((g) => ({
		id: g,
		title: GLOSSARY_GROUPS[g],
		entries: Object.entries(GLOSSARY).filter(([, e]) => e.group === g)
	}));

	// Al llegar desde un «?» (/ayuda#termino), se resalta ese término.
	let marked = $state('');
	onMount(() => {
		const id = decodeURIComponent(location.hash.slice(1));
		if (!GLOSSARY[id]) return;
		marked = id;
		requestAnimationFrame(() => document.getElementById(id)?.scrollIntoView({ block: 'center' }));
	});
</script>

<svelte:head><title>Qué significa cada cosa · Resguardo</title></svelte:head>

<div class="page">
	<header class="page-head">
		<div>
			<h1 class="page-title">Qué significa cada cosa</h1>
			<p class="page-sub">
				Los estados, las cifras y las comprobaciones de esta web, en palabras sencillas y con qué hacer. Casi todo se arregla en Resguardo,
				en el equipo: desde aquí solo se mira (y se puede pedir «Copiar ahora»).
			</p>
		</div>
	</header>

	<nav class="toc" aria-label="Apartados">
		{#each groups as g (g.id)}<a href="#g-{g.id}">{g.title}</a>{/each}
	</nav>

	{#each groups as g (g.id)}
		<section class="card group" id="g-{g.id}" aria-labelledby="t-{g.id}">
			<h2 class="section-title" id="t-{g.id}">{g.title}</h2>
			<dl>
				{#each g.entries as [id, e] (id)}
					<div class="entry" class:marked={marked === id} {id}>
						<dt>{e.title}</dt>
						<dd>
							<p>{e.text}</p>
							{#if e.todo}<p class="todo"><span>Qué hacer:</span> {e.todo}</p>{/if}
						</dd>
					</div>
				{/each}
			</dl>
		</section>
	{/each}
</div>

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
	.toc {
		display: flex;
		flex-wrap: wrap;
		gap: var(--sp-2);
	}
	.toc a {
		padding: 4px 10px;
		font-size: var(--fs-sm);
		font-weight: 500;
		color: var(--text-2);
		background: var(--surface-2);
		border-radius: 999px;
	}
	.toc a:hover {
		color: var(--text-1);
		text-decoration: none;
	}
	.group {
		display: flex;
		flex-direction: column;
		gap: var(--sp-2);
		padding: var(--sp-5);
		scroll-margin-top: calc(var(--header-h) + 16px);
	}
	dl {
		margin: 0;
	}
	.entry {
		display: grid;
		grid-template-columns: 200px minmax(0, 1fr);
		gap: var(--sp-4);
		padding: var(--sp-3) var(--sp-2);
		border-top: 1px solid var(--border);
		border-radius: var(--radius-sm);
		scroll-margin-top: calc(var(--header-h) + 16px);
	}
	.entry.marked {
		background: var(--accent-soft);
	}
	dt {
		font-weight: 500;
	}
	dd {
		display: flex;
		flex-direction: column;
		gap: 4px;
		margin: 0;
		font-size: var(--fs-sm);
		line-height: var(--lh-sm);
		color: var(--text-2);
	}
	.todo span {
		font-weight: 500;
		color: var(--text-1);
	}
	@media (max-width: 640px) {
		.entry {
			grid-template-columns: minmax(0, 1fr);
			gap: 4px;
		}
	}
</style>
