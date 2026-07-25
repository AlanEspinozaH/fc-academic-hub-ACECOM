import { Miniflare } from 'miniflare';
import { createR2ResourceObjectStore } from './resource-object-store';
import { describe, expect, it } from 'vitest';

const BUCKET_BINDING = 'ACADEMIC_RESOURCES';
const STORAGE_KEY =
	'resources/11111111-2222-3333-4444-555555555555/aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';

const WORKER_SCRIPT = `
export default {
	async fetch() {
		return new Response('ok');
	},
};
`;

describe('R2 resource object store with local Miniflare', () => {
	it('writes, reads, detects missing, and deletes a generic_v2 object in local R2', async () => {
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

			await expect(store.read(STORAGE_KEY)).resolves.toEqual({ bytes });
			await expect(store.read(`${STORAGE_KEY}-missing`)).resolves.toBeNull();

			await store.delete(STORAGE_KEY);

			await expect(store.read(STORAGE_KEY)).resolves.toBeNull();
		} finally {
			await miniflare.dispose();
		}
	});
});
