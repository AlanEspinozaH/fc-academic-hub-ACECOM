import { describe, expect, it } from 'vitest';
import {
	CURRENT_RESOURCE_STORAGE_KEY_VERSION,
	ResourceStorageKeyError,
	derivePrivateResourceStorageKey,
	type ResourceStorageKeyVersion,
} from './resource-storage-key';

const RESOURCE_ID = '11111111-2222-3333-4444-555555555555';
const FILE_ID = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
const BASE_KEY = `resources/${RESOURCE_ID}/${FILE_ID}`;

describe('private resource storage key', () => {
	it('derives the legacy PDF layout with its .pdf suffix', () => {
		expect(derivePrivateResourceStorageKey('legacy_pdf_v1', RESOURCE_ID, FILE_ID)).toBe(
			`${BASE_KEY}.pdf`,
		);
	});

	it('derives the generic v2 layout without a filename suffix', () => {
		expect(derivePrivateResourceStorageKey('generic_v2', RESOURCE_ID, FILE_ID)).toBe(BASE_KEY);
		expect(CURRENT_RESOURCE_STORAGE_KEY_VERSION).toBe('generic_v2');
	});

	it('canonicalizes uppercase UUID characters', () => {
		expect(
			derivePrivateResourceStorageKey(
				'generic_v2',
				RESOURCE_ID.toUpperCase(),
				FILE_ID.toUpperCase(),
			),
		).toBe(BASE_KEY);
	});

	it('canonicalizes surrounding whitespace', () => {
		expect(
			derivePrivateResourceStorageKey('generic_v2', ` ${RESOURCE_ID} `, `\t${FILE_ID}\n`),
		).toBe(BASE_KEY);
	});

	it('rejects an invalid resource id without exposing it in the error message', () => {
		const invalidResourceId = '../../private/object';

		expect(() => derivePrivateResourceStorageKey('generic_v2', invalidResourceId, FILE_ID)).toThrow(
			ResourceStorageKeyError,
		);

		try {
			derivePrivateResourceStorageKey('generic_v2', invalidResourceId, FILE_ID);
		} catch (error) {
			expect(error).toMatchObject({
				name: 'ResourceStorageKeyError',
				code: 'INVALID_RESOURCE_ID',
				message: 'resource id must be a canonical UUID',
			});

			expect((error as Error).message).not.toContain(invalidResourceId);
		}
	});

	it('rejects an invalid file id without exposing it in the error message', () => {
		const invalidFileId = 'not-a-file-uuid';

		expect(() => derivePrivateResourceStorageKey('generic_v2', RESOURCE_ID, invalidFileId)).toThrow(
			ResourceStorageKeyError,
		);

		try {
			derivePrivateResourceStorageKey('generic_v2', RESOURCE_ID, invalidFileId);
		} catch (error) {
			expect(error).toMatchObject({
				name: 'ResourceStorageKeyError',
				code: 'INVALID_FILE_ID',
				message: 'file id must be a canonical UUID',
			});

			expect((error as Error).message).not.toContain(invalidFileId);
		}
	});

	it('rejects an unsupported version without falling back to a known layout', () => {
		const unsupportedVersion = 'legacy_default' as ResourceStorageKeyVersion;

		expect(() => derivePrivateResourceStorageKey(unsupportedVersion, RESOURCE_ID, FILE_ID)).toThrow(
			expect.objectContaining({
				code: 'UNSUPPORTED_STORAGE_KEY_VERSION',
				message: 'unsupported resource storage key version',
			}),
		);
	});
});
