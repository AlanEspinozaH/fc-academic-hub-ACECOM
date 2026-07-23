import { describe, expect, it } from 'vitest';
import { ResourceStorageKeyError, derivePrivateResourceStorageKey } from './resource-storage-key';

const RESOURCE_ID = '11111111-2222-3333-4444-555555555555';
const FILE_ID = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

describe('private resource storage key', () => {
	it('derives the PostgreSQL-compatible private R2 key', () => {
		expect(derivePrivateResourceStorageKey(RESOURCE_ID, FILE_ID)).toBe(
			'resources/11111111-2222-3333-4444-555555555555/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.pdf',
		);
	});

	it('canonicalizes uppercase UUID characters', () => {
		expect(derivePrivateResourceStorageKey(RESOURCE_ID.toUpperCase(), FILE_ID.toUpperCase())).toBe(
			'resources/11111111-2222-3333-4444-555555555555/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.pdf',
		);
	});

	it('canonicalizes surrounding whitespace', () => {
		expect(derivePrivateResourceStorageKey(` ${RESOURCE_ID} `, `\t${FILE_ID}\n`)).toBe(
			'resources/11111111-2222-3333-4444-555555555555/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee.pdf',
		);
	});

	it('rejects an invalid resource id without exposing it in the error message', () => {
		const invalidResourceId = '../../private/object';

		expect(() => derivePrivateResourceStorageKey(invalidResourceId, FILE_ID)).toThrow(
			ResourceStorageKeyError,
		);

		try {
			derivePrivateResourceStorageKey(invalidResourceId, FILE_ID);
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

		expect(() => derivePrivateResourceStorageKey(RESOURCE_ID, invalidFileId)).toThrow(
			ResourceStorageKeyError,
		);

		try {
			derivePrivateResourceStorageKey(RESOURCE_ID, invalidFileId);
		} catch (error) {
			expect(error).toMatchObject({
				name: 'ResourceStorageKeyError',
				code: 'INVALID_FILE_ID',
				message: 'file id must be a canonical UUID',
			});

			expect((error as Error).message).not.toContain(invalidFileId);
		}
	});
});
