import { Miniflare } from 'miniflare';
import { createR2ResourceObjectStore } from './resource-object-store';
import { describe, expect, it } from 'vitest';

const BUCKET_BINDING = 'ACADEMIC_RESOURCES';
const STORAGE_KEY = 'integration/private-resource.pdf';

const WORKER_SCRIPT = `
export default {
	async fetch() {
		return new Response('ok');
	},
};
`;

describe('R2 resource object store with local Miniflare', () => {
	it('writes and deletes an object in local R2', async () => {
		const miniflare = new Miniflare({
			modules: true,
			script: WORKER_SCRIPT,
			r2Buckets: [BUCKET_BINDING],
		});

		try {
			const bucket = (await miniflare.getR2Bucket(BUCKET_BINDING)) as unknown as R2Bucket;
			const store = createR2ResourceObjectStore(bucket);
			const bytes = new TextEncoder().encode('%PDF-1.7\nintegration\n%%EOF\n');

			await store.write({
				storageKey: STORAGE_KEY,
				bytes,
				contentType: 'application/pdf',
			});

			const storedObject = await bucket.get(STORAGE_KEY);

			expect(storedObject).not.toBeNull();

			if (storedObject === null) {
				throw new Error('Expected local R2 object to exist');
			}

			expect(storedObject.httpMetadata?.contentType).toBe('application/pdf');

			const storedBytes = new Uint8Array(await storedObject.arrayBuffer());

			expect(storedBytes).toEqual(bytes);

			await store.delete(STORAGE_KEY);

			expect(await bucket.get(STORAGE_KEY)).toBeNull();
		} finally {
			await miniflare.dispose();
		}
	});
});
