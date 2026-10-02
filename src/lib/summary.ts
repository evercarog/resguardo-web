// Un repositorio en una frase (como en la app de escritorio): cómo está, los
// hechos que importan y qué falta. «Siigo está protegido. Última copia hace
// 12 min, la nube va al día y se verificó hace 2 días. Falta: preparar el kit
// de recuperación.» Solo con los datos que ya informa el equipo.
import { formatRelative } from '$lib/format';
import { elapsedLabel, lastCheck, pauseUntilLabel, repoStatus } from '$lib/status';
import type { Protection, Repo } from '$lib/types';

type Status = ReturnType<typeof repoStatus>;

/** Qué falta, en pocas palabras, para cada comprobación de la protección. */
const MISSING: Record<string, { add: string; fix: string }> = {
	copias: { add: 'programar las copias automáticas', fix: 'revisar las copias automáticas' },
	borrado: { add: 'protegerlo contra borrado', fix: 'comprobar la protección contra borrado' },
	externa: { add: 'configurar una copia externa', fix: 'revisar la copia externa' },
	verificacion: { add: 'programar la verificación', fix: 'revisar la verificación' },
	restauracion: { add: 'programar una prueba de restauración', fix: 'revisar la prueba de restauración' },
	kit: { add: 'preparar el kit de recuperación', fix: 'preparar un kit de recuperación nuevo' },
	retencion: { add: 'definir la retención', fix: 'revisar la retención' }
};

/** Lo que falta para estar protegido del todo, lo más grave primero. */
export function missingOf(p: Protection | null | undefined): string[] {
	if (!p) return [];
	const items = p.items.filter((i) => i.state === 'bad' || i.state === 'warn');
	items.sort((a, b) => (a.state === b.state ? 0 : a.state === 'bad' ? -1 : 1));
	return items.map((i) => {
		const m = MISSING[i.id];
		if (!m) return i.label.toLowerCase();
		// «La última falló», «Atrasada», «cambió»…: hay algo que revisar; «Sin…»: falta ponerlo.
		const failing = /fall|error|atrasad|cambi|frenad/i.test(i.detail ?? '');
		return failing ? m.fix : m.add;
	});
}

function join(list: string[]) {
	return list.length < 2 ? (list[0] ?? '') : `${list.slice(0, -1).join(', ')} y ${list.at(-1)}`;
}
const cap = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);

export function repoSummary(repo: Repo, status: Status, now = Date.now()) {
	const name = repo.name;
	const missing = missingOf(repo.protection);

	// 1. Cómo está.
	let lead: string;
	let tone: 'ok' | 'warn' | 'bad' | 'paused' | 'neutral';
	if (repo.offsite_hold) {
		lead = `${name} tiene un cambio inusual por revisar: la subida a la nube está frenada.`;
		tone = 'bad';
	} else if (status.level === 'failed') {
		lead = `La última copia de ${name} falló.`;
		tone = 'bad';
	} else if (status.level === 'overdue' && status.since !== null) {
		lead = `${name} lleva ${elapsedLabel(status.since)} sin copias.`;
		tone = 'bad';
	} else if (status.level === 'late' && status.since !== null) {
		lead = `${name} va con ${elapsedLabel(status.since - status.expected)} de retraso.`;
		tone = 'warn';
	} else if (status.level === 'paused') {
		lead = `Las copias de ${name} están en pausa ${pauseUntilLabel(status.pause.until)}.`;
		tone = 'paused';
	} else if (status.level === 'empty') {
		lead = `${name} todavía no tiene versiones.`;
		tone = 'neutral';
	} else if (missing.length) {
		lead = `${name} está al día.`;
		tone = 'ok';
	} else {
		lead = `${name} está protegido.`;
		tone = 'ok';
	}

	// 2. Los hechos: última copia, la nube y la verificación.
	const facts: string[] = [];
	const at = lastCheck(repo).at;
	if (at) facts.push(`última copia ${formatRelative(at, now)}`);
	const off = repo.maintenance?.offsite;
	if (off && !repo.offsite_hold) {
		const up = repo.offsite_run?.finished ? new Date(repo.offsite_run.finished).getTime() : null;
		const local = repo.last_snapshot_at ? new Date(repo.last_snapshot_at).getTime() : null;
		if (repo.offsite_run?.result === 'error') facts.push('la última subida a la nube falló');
		else if (up === null) facts.push('todavía no se ha subido nada a la nube');
		else if (local === null || up >= local) facts.push('la nube va al día');
		else facts.push(`la nube va ${elapsedLabel((local - up) / 3_600_000)} por detrás`);
	}
	if (repo.maintenance?.verify && repo.verify_run) {
		const when = formatRelative(repo.verify_run.finished ?? repo.verify_run.started, now);
		facts.push(repo.verify_run.result === 'error' ? `la verificación de ${when} encontró errores` : `se verificó ${when}`);
	}
	if (repo.maintenance?.restore_test && repo.restore_test_run?.result === 'error') facts.push('la última prueba de restauración falló');

	const factsText = facts.length ? `${cap(join(facts))}.` : '';
	const missingText = missing.length ? `Falta: ${join(missing)}.` : '';
	return {
		tone,
		lead,
		facts: factsText,
		missing: missingText,
		text: [lead, factsText, missingText].filter(Boolean).join(' '),
		/** Versión corta para las tarjetas: cómo está y lo primero que falta. */
		short: [lead, missing.length ? `Falta: ${missing[0]}${missing.length > 1 ? ` y ${missing.length - 1} más` : ''}.` : ''].filter(Boolean).join(' ')
	};
}
