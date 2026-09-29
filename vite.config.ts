import adapter from '@sveltejs/adapter-static';
import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig, loadEnv } from 'vite';

// La CSP solo permite hablar con el proyecto de Supabase de esta web (no con
// cualquier *.supabase.co): si algo llegara a ejecutarse, no podría enviar
// datos a otro proyecto.
const nodeEnv = (globalThis as { process?: { env: Record<string, string | undefined>; cwd(): string } }).process;
const env = { ...loadEnv('production', nodeEnv?.cwd() ?? '.', 'PUBLIC_'), ...nodeEnv?.env };
const supabaseHost = env.PUBLIC_SUPABASE_URL ? new URL(env.PUBLIC_SUPABASE_URL).host : '*.supabase.co';

export default defineConfig({
	plugins: [
		sveltekit({
			compilerOptions: {
				// Force runes mode for the project, except for libraries. Can be removed in svelte 6.
				runes: ({ filename }) =>
					filename.split(/[/\\]/).includes('node_modules') ? undefined : true
			},
			// Web estática (SPA): toda la lógica y los datos están en Supabase, así que
			// se puede publicar igual en Vercel, Cloudflare Pages o cualquier servidor.
			adapter: adapter({ fallback: 'index.html' }),
			// La web solo ejecuta su propio código (con huellas) y solo habla con Supabase.
			csp: {
				mode: 'hash',
				directives: {
					'default-src': ['self'],
					'script-src': ['self'],
					'style-src': ['self', 'unsafe-inline'],
					'img-src': ['self', 'data:', 'blob:'],
					'font-src': ['self'],
					'connect-src': ['self', `https://${supabaseHost}` as `https://${string}.${string}`, `wss://${supabaseHost}` as `wss://${string}.${string}`],
					'worker-src': ['self'],
					'manifest-src': ['self'],
					'object-src': ['none'],
					'base-uri': ['none'],
					'form-action': ['self']
				}
			}
		})
	]
});