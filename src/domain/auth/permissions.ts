import { isAppRole, type AppRole } from './roles';

export const APP_PERMISSIONS = [
	'catalog.read',
	'restricted_material.read',
	'submission.create',
	'submission.review',
	'submission.publish',
	'role.manage',
	'account.suspend',
	'audit.read',
] as const;

export type AppPermission = (typeof APP_PERMISSIONS)[number];

const appPermissionSet: ReadonlySet<string> = new Set(APP_PERMISSIONS);

export const isAppPermission = (value: unknown): value is AppPermission =>
	typeof value === 'string' && appPermissionSet.has(value);

const permissionsByRole = {
	student: ['catalog.read', 'restricted_material.read'],
	contributor: ['catalog.read', 'restricted_material.read', 'submission.create'],
	reviewer: ['catalog.read', 'restricted_material.read', 'submission.create', 'submission.review'],
	moderator: [
		'catalog.read',
		'restricted_material.read',
		'submission.create',
		'submission.review',
		'submission.publish',
	],
	administrator: [
		'catalog.read',
		'restricted_material.read',
		'submission.create',
		'submission.review',
		'submission.publish',
		'role.manage',
		'account.suspend',
		'audit.read',
	],
} as const satisfies Record<AppRole, readonly AppPermission[]>;

export const permissionsForRole = (role: unknown): ReadonlySet<AppPermission> => {
	if (!isAppRole(role)) {
		return new Set<AppPermission>();
	}

	return new Set(permissionsByRole[role]);
};

export const roleHasPermission = (role: unknown, permission: unknown): boolean => {
	if (!isAppPermission(permission)) {
		return false;
	}

	return permissionsForRole(role).has(permission);
};

export const anyRoleHasPermission = (roles: ReadonlyArray<unknown>, permission: unknown): boolean =>
	roles.some((role) => roleHasPermission(role, permission));
