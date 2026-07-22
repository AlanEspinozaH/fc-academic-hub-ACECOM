import { describe, expect, it } from 'vitest';
import { APP_ROLES, isAppRole } from './roles';
import {
	APP_PERMISSIONS,
	anyRoleHasPermission,
	isAppPermission,
	permissionsForRole,
	roleHasPermission,
	type AppPermission,
} from './permissions';

const permissions = (role: unknown): ReadonlyArray<AppPermission> =>
	Array.from(permissionsForRole(role)).sort();

describe('RBAC permissions', () => {
	it('validates role and permission input at runtime', () => {
		expect(APP_ROLES).toEqual(['student', 'contributor', 'reviewer', 'moderator', 'administrator']);
		expect(APP_PERMISSIONS).toEqual([
			'catalog.read',
			'restricted_material.read',
			'submission.create',
			'submission.review',
			'submission.publish',
			'role.manage',
			'account.suspend',
			'audit.read',
		]);
		expect(isAppRole('reviewer')).toBe(true);
		expect(isAppRole('owner')).toBe(false);
		expect(isAppPermission('audit.read')).toBe(true);
		expect(isAppPermission('audit.write')).toBe(false);
	});

	it('returns explicit permission sets for each role', () => {
		expect(permissions('student')).toEqual(['catalog.read', 'restricted_material.read']);
		expect(permissions('contributor')).toEqual([
			'catalog.read',
			'restricted_material.read',
			'submission.create',
		]);
		expect(permissions('reviewer')).toEqual([
			'catalog.read',
			'restricted_material.read',
			'submission.create',
			'submission.review',
		]);
		expect(permissions('moderator')).toEqual([
			'catalog.read',
			'restricted_material.read',
			'submission.create',
			'submission.publish',
			'submission.review',
		]);
		expect(permissions('administrator')).toEqual([...APP_PERMISSIONS].sort());
	});

	it('answers permission checks without numeric role ordering', () => {
		expect(roleHasPermission('reviewer', 'submission.review')).toBe(true);
		expect(roleHasPermission('reviewer', 'submission.publish')).toBe(false);
		expect(roleHasPermission('moderator', 'role.manage')).toBe(false);
		expect(roleHasPermission('administrator', 'role.manage')).toBe(true);
		expect(roleHasPermission('administrator', 'audit.write')).toBe(false);
		expect(roleHasPermission('owner', 'audit.read')).toBe(false);
	});

	it('checks permissions across multiple externally supplied roles', () => {
		expect(anyRoleHasPermission(['student', 'reviewer'], 'submission.review')).toBe(true);
		expect(anyRoleHasPermission(['student', 'moderator'], 'role.manage')).toBe(false);
		expect(anyRoleHasPermission(['unknown', 'administrator'], 'audit.read')).toBe(true);
		expect(anyRoleHasPermission([], 'catalog.read')).toBe(false);
	});
});
