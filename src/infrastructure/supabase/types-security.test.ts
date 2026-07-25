import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { describe, expect, expectTypeOf, it } from 'vitest';
import type { SupabaseDatabase } from './types';

const generatedTypesSource = readFileSync(
	fileURLToPath(new URL('./database.generated.ts', import.meta.url)),
	'utf8',
);

type RegisterUploadArgs =
	SupabaseDatabase['public']['Functions']['register_resource_file_upload']['Args'];

type FinalizeUploadArgs =
	SupabaseDatabase['public']['Functions']['finalize_resource_file_upload']['Args'];

type AbortUploadArgs =
	SupabaseDatabase['public']['Functions']['abort_resource_file_upload']['Args'];

type RegisterUploadResult =
	SupabaseDatabase['public']['Functions']['register_resource_file_upload']['Returns'];

type IdentityKind = SupabaseDatabase['public']['Enums']['identity_kind'];

type ProfileIdentityKind = SupabaseDatabase['public']['Tables']['profiles']['Row']['identity_kind'];

type AppEntitlement = SupabaseDatabase['public']['Enums']['app_entitlement'];

type ResourceVisibility = SupabaseDatabase['public']['Enums']['resource_visibility'];

type ResourceRightsStatus = SupabaseDatabase['public']['Enums']['resource_rights_status'];

type ResourceFileKind = SupabaseDatabase['public']['Enums']['resource_file_kind'];

type ResourceStorageKeyVersion =
	SupabaseDatabase['public']['Enums']['resource_storage_key_version'];

type ResourceFileRow = SupabaseDatabase['public']['Tables']['resource_files']['Row'];

type GrantEntitlementArgs =
	SupabaseDatabase['public']['Functions']['grant_user_entitlement']['Args'];

type RevokeEntitlementArgs =
	SupabaseDatabase['public']['Functions']['revoke_user_entitlement']['Args'];

type GrantEntitlementResult =
	SupabaseDatabase['public']['Functions']['grant_user_entitlement']['Returns'];

type RevokeEntitlementResult =
	SupabaseDatabase['public']['Functions']['revoke_user_entitlement']['Returns'];

type HasPrivateSchema = 'private' extends keyof SupabaseDatabase ? true : false;

type RegisterAcceptsStorageKey = 'storage_key' extends keyof RegisterUploadArgs ? true : false;

type RegisterAcceptsStorageKeyVersion = 'storage_key_version' extends keyof RegisterUploadArgs
	? true
	: false;

describe('generated Supabase database types', () => {
	it('contains only the public database contract', () => {
		expect(generatedTypesSource).not.toMatch(/^[\t ]*private:/m);
		expect(generatedTypesSource).not.toMatch(/^[\t ]*storage_key:/m);
		expect(generatedTypesSource).not.toContain('service_role');

		expect(generatedTypesSource).toContain('register_resource_file_upload');
		expect(generatedTypesSource).toContain('finalize_resource_file_upload');
		expect(generatedTypesSource).toContain('abort_resource_file_upload');
		expect(generatedTypesSource).toContain('mark_resource_file_failed');
	});

	it('exposes the atomic upload RPC signatures without a caller-controlled storage key', () => {
		expectTypeOf<HasPrivateSchema>().toEqualTypeOf<false>();
		expectTypeOf<RegisterAcceptsStorageKey>().toEqualTypeOf<false>();
		expectTypeOf<RegisterAcceptsStorageKeyVersion>().toEqualTypeOf<false>();

		expectTypeOf<keyof RegisterUploadArgs>().toEqualTypeOf<
			| 'byte_size'
			| 'content_type'
			| 'display_filename'
			| 'file_kind'
			| 'normalized_extension'
			| 'resource_id'
			| 'sha256'
		>();

		expectTypeOf<keyof FinalizeUploadArgs>().toEqualTypeOf<'comment' | 'file_id' | 'sha256'>();

		expectTypeOf<keyof AbortUploadArgs>().toEqualTypeOf<'file_id' | 'reason'>();
		expectTypeOf<RegisterUploadResult>().toEqualTypeOf<string>();
	});

	it('exposes identity_kind consistently on profiles', () => {
		expectTypeOf<IdentityKind>().toEqualTypeOf<'institutional' | 'external_authorized'>();
		expectTypeOf<ProfileIdentityKind>().toEqualTypeOf<IdentityKind>();
	});

	it('exposes canonical ResourceFile metadata and explicit storage layouts', () => {
		expectTypeOf<ResourceFileKind>().toEqualTypeOf<
			'pdf' | 'image' | 'markdown' | 'tex' | 'text' | 'source'
		>();
		expectTypeOf<ResourceStorageKeyVersion>().toEqualTypeOf<'legacy_pdf_v1' | 'generic_v2'>();
		expectTypeOf<ResourceFileRow['file_kind']>().toEqualTypeOf<ResourceFileKind>();
		expectTypeOf<ResourceFileRow['normalized_extension']>().toEqualTypeOf<string>();
		expectTypeOf<
			ResourceFileRow['storage_key_version']
		>().toEqualTypeOf<ResourceStorageKeyVersion>();
	});

	it('exposes the v1 entitlement and resource audience contracts', () => {
		expectTypeOf<AppEntitlement>().toEqualTypeOf<'privileged_material.read'>();

		expectTypeOf<ResourceVisibility>().toEqualTypeOf<
			'private' | 'restricted' | 'public' | 'privileged'
		>();

		expectTypeOf<ResourceRightsStatus>().toEqualTypeOf<
			| 'pending'
			| 'own-work'
			| 'authorized'
			| 'institutional'
			| 'bibliographic-reference-only'
			| 'copyright-restricted'
			| 'open-license'
			| 'public-domain'
		>();

		expectTypeOf<keyof GrantEntitlementArgs>().toEqualTypeOf<
			'entitlement' | 'reason' | 'target_user_id'
		>();
		expectTypeOf<keyof RevokeEntitlementArgs>().toEqualTypeOf<
			'entitlement' | 'reason' | 'target_user_id'
		>();

		expectTypeOf<GrantEntitlementArgs['entitlement']>().toEqualTypeOf<AppEntitlement>();
		expectTypeOf<RevokeEntitlementArgs['entitlement']>().toEqualTypeOf<AppEntitlement>();

		expectTypeOf<GrantEntitlementResult>().toEqualTypeOf<number>();
		expectTypeOf<RevokeEntitlementResult>().toEqualTypeOf<number>();
	});
});
