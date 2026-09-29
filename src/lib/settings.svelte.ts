// Apariencia (misma que la app de escritorio). Se guarda en este navegador.
export type ThemeMode = 'system' | 'light' | 'dark' | 'black';
export type Accent = 'teal' | 'blue' | 'indigo' | 'violet' | 'rose' | 'amber' | 'graphite';

export const THEMES: { id: ThemeMode; label: string }[] = [
	{ id: 'system', label: 'Sistema' },
	{ id: 'light', label: 'Claro' },
	{ id: 'dark', label: 'Oscuro' },
	{ id: 'black', label: 'Negro' }
];

export const ACCENTS: { id: Accent; label: string; light: string; dark: string }[] = [
	{ id: 'teal', label: 'Verde azulado', light: '#0d7a69', dark: '#3cc4ad' },
	{ id: 'blue', label: 'Azul', light: '#1f63d8', dark: '#5b9dff' },
	{ id: 'indigo', label: 'Índigo', light: '#4f46e5', dark: '#8e8cff' },
	{ id: 'violet', label: 'Violeta', light: '#7c3aed', dark: '#b38bff' },
	{ id: 'rose', label: 'Rosa', light: '#cf2f68', dark: '#ff7aa6' },
	{ id: 'amber', label: 'Ámbar', light: '#b45309', dark: '#f2b33d' },
	{ id: 'graphite', label: 'Grafito', light: '#3f4b5c', dark: '#aab6c6' }
];

const KEY = 'resguardo:apariencia';

function load(): { theme: ThemeMode; accent: Accent } {
	const fallback = { theme: 'system' as ThemeMode, accent: 'teal' as Accent };
	try {
		const saved = JSON.parse(localStorage.getItem(KEY) ?? '{}');
		return {
			theme: THEMES.some((t) => t.id === saved.theme) ? saved.theme : fallback.theme,
			accent: ACCENTS.some((a) => a.id === saved.accent) ? saved.accent : fallback.accent
		};
	} catch {
		return fallback;
	}
}

export const appearance = $state(load());

function apply() {
	const root = document.documentElement;
	if (appearance.theme === 'system') root.removeAttribute('data-theme');
	else root.dataset.theme = appearance.theme;
	if (appearance.accent === 'teal') root.removeAttribute('data-accent');
	else root.dataset.accent = appearance.accent;
	try {
		localStorage.setItem(KEY, JSON.stringify(appearance));
	} catch {
		/* sin almacenamiento */
	}
}

export const initAppearance = apply;

export function setTheme(theme: ThemeMode) {
	appearance.theme = theme;
	apply();
}

export function setAccent(accent: Accent) {
	appearance.accent = accent;
	apply();
}
