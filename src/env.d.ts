type SupabaseServerClient = import('./infrastructure/supabase/server').SupabaseServerClient;

type AuthStatus = 'unconfigured' | 'anonymous' | 'authenticated' | 'error';

interface AuthenticatedUser {
	readonly id: string;
	readonly email: string | null;
}

interface AuthContext {
	readonly status: AuthStatus;
	readonly user: AuthenticatedUser | null;
	readonly supabase: SupabaseServerClient | null;
}

interface ImportMetaEnv {
	readonly PUBLIC_SUPABASE_URL: string;
	readonly PUBLIC_SUPABASE_PUBLISHABLE_KEY: string;
}

interface ImportMeta {
	readonly env: ImportMetaEnv;
}

declare namespace App {
	interface Locals {
		auth: AuthContext;
	}
}
