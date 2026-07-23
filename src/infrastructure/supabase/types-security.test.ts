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

type HasPrivateSchema = 'private' extends keyof SupabaseDatabase ? true : false;

type RegisterAcceptsStorageKey = 'storage_key' extends keyof RegisterUploadArgs ? true : false;

describe('generated Supabase database types', () => {
	it('contains only the public database contract', () => {
		expect(generatedTypesSource).not.toMatch(/^[\t ]*private:/m);
		expect(generatedTypesSource).not.toContain('storage_key');
		expect(generatedTypesSource).not.toContain('service_role');

		expect(generatedTypesSource).toContain('register_resource_file_upload');
		expect(generatedTypesSource).toContain('finalize_resource_file_upload');
		expect(generatedTypesSource).toContain('abort_resource_file_upload');
		expect(generatedTypesSource).toContain('mark_resource_file_failed');
	});

	it('exposes the atomic upload RPC signatures without a caller-controlled storage key', () => {
		expectTypeOf<HasPrivateSchema>().toEqualTypeOf<false>();
		expectTypeOf<RegisterAcceptsStorageKey>().toEqualTypeOf<false>();

		expectTypeOf<keyof RegisterUploadArgs>().toEqualTypeOf<
			'byte_size' | 'content_type' | 'display_filename' | 'resource_id' | 'sha256'
		>();

		expectTypeOf<keyof FinalizeUploadArgs>().toEqualTypeOf<'comment' | 'file_id' | 'sha256'>();

		expectTypeOf<keyof AbortUploadArgs>().toEqualTypeOf<'file_id' | 'reason'>();
		expectTypeOf<RegisterUploadResult>().toEqualTypeOf<string>();
	});
});
