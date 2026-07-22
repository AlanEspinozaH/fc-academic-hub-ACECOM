export const APP_ROLES = [
	'student',
	'contributor',
	'reviewer',
	'moderator',
	'administrator',
] as const;

export type AppRole = (typeof APP_ROLES)[number];

const appRoleSet: ReadonlySet<string> = new Set(APP_ROLES);

export const isAppRole = (value: unknown): value is AppRole =>
	typeof value === 'string' && appRoleSet.has(value);
