import { createClient } from '@supabase/supabase-js';
import { PUBLIC_SUPABASE_PUBLISHABLE_KEY, PUBLIC_SUPABASE_URL } from '$env/static/public';

/** Cliente de Supabase con la clave publicable: los permisos los decide la base de datos (RLS). */
export const supabase = createClient(PUBLIC_SUPABASE_URL, PUBLIC_SUPABASE_PUBLISHABLE_KEY, {
	auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true }
});
