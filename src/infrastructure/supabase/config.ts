const publicSupabaseUrlKey = 'PUBLIC_SUPABASE_URL';
const publicSupabasePublishableKey = 'PUBLIC_SUPABASE_PUBLISHABLE_KEY';

export type SupabaseEnv = Readonly<
	Partial<Record<typeof publicSupabaseUrlKey | typeof publicSupabasePublishableKey, string>>
>;

export interface SupabaseConfig {
	readonly url: string;
	readonly publishableKey: string;
}

const placeholderMarkers = [
	'placeholder',
	'replace-with',
	'replace_me',
	'change-me',
	'change_me',
	'your-',
	'your_',
	'example',
	'<',
	'>',
	'{',
	'}',
] as const;

const secretKeyPrefix = ['sb', 'secret'].join('_') + '_';

const readRequiredEnvValue = (env: SupabaseEnv, key: keyof SupabaseEnv, label: string): string => {
	const value = env[key]?.trim();

	if (!value) {
		throw new Error(`Missing ${label}. Set ${key} in .env.local.`);
	}

	if (isPlaceholderValue(value)) {
		throw new Error(`Invalid ${label}. Replace the placeholder value.`);
	}

	return value;
};

const isPlaceholderValue = (value: string): boolean => {
	const normalizedValue = value.toLowerCase();

	return placeholderMarkers.some((marker) => normalizedValue.includes(marker));
};

const validateSupabaseUrl = (url: string): void => {
	let parsedUrl: URL;

	try {
		parsedUrl = new URL(url);
	} catch {
		throw new Error('Invalid Supabase URL. Use a valid http or https URL.');
	}

	if (parsedUrl.protocol !== 'http:' && parsedUrl.protocol !== 'https:') {
		throw new Error('Invalid Supabase URL. Use http or https.');
	}
};

const validatePublishableKey = (publishableKey: string): void => {
	if (publishableKey.toLowerCase().startsWith(secretKeyPrefix)) {
		throw new Error('Invalid Supabase publishable key. Use a publishable key.');
	}
};

export const resolveSupabaseConfig = (env: SupabaseEnv): SupabaseConfig => {
	const url = readRequiredEnvValue(env, publicSupabaseUrlKey, 'Supabase URL');
	const publishableKey = readRequiredEnvValue(
		env,
		publicSupabasePublishableKey,
		'Supabase publishable key',
	);

	validateSupabaseUrl(url);
	validatePublishableKey(publishableKey);

	return Object.freeze({
		url,
		publishableKey,
	});
};

export const getSupabaseConfig = (env: SupabaseEnv = import.meta.env): SupabaseConfig =>
	resolveSupabaseConfig(env);
