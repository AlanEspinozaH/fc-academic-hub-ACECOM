import { describe, expect, it, vi } from 'vitest';
import {
	ResourceUploadPersistenceError,
	createSupabaseResourceUploadPersistence,
} from './resource-upload-persistence';
import type { SupabaseServerClient } from './server';

const RESOURCE_ID = '11111111-2222-3333-4444-555555555555';
const FILE_ID = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
const SHA256 = 'a'.repeat(64);

const makeClient = () => {
	const rpc = vi.fn();

	const client = {
		rpc,
	} as unknown as Pick<SupabaseServerClient, 'rpc'>;

	return { client, rpc };
};

describe('Supabase resource upload persistence', () => {
	it('reserves file metadata through the registration RPC', async () => {
		const { client, rpc } = makeClient();
		const persistence = createSupabaseResourceUploadPersistence(client);

		rpc.mockResolvedValueOnce({
			data: FILE_ID,
			error: null,
		});

		await expect(
			persistence.reserve({
				resourceId: RESOURCE_ID,
				displayFilename: 'exam.pdf',
				contentType: 'application/pdf',
				byteSize: 1234,
				sha256: SHA256,
			}),
		).resolves.toBe(FILE_ID);

		expect(rpc).toHaveBeenCalledTimes(1);
		expect(rpc).toHaveBeenCalledWith('register_resource_file_upload', {
			resource_id: RESOURCE_ID,
			display_filename: 'exam.pdf',
			content_type: 'application/pdf',
			byte_size: 1234,
			sha256: SHA256,
		});
	});

	it('retries finalization once after a status-zero transport response', async () => {
		const { client, rpc } = makeClient();
		const persistence = createSupabaseResourceUploadPersistence(client);

		rpc.mockResolvedValueOnce({
			data: null,
			error: {
				message: 'TypeError: fetch failed',
			},
			status: 0,
			statusText: '',
		});

		rpc.mockResolvedValueOnce({
			data: FILE_ID,
			error: null,
			status: 200,
			statusText: 'OK',
		});

		await expect(
			persistence.finalize({
				fileId: FILE_ID,
				sha256: SHA256,
			}),
		).resolves.toBeUndefined();

		expect(rpc).toHaveBeenCalledTimes(2);
	});

	it('aborts a reservation through the abort RPC', async () => {
		const { client, rpc } = makeClient();
		const persistence = createSupabaseResourceUploadPersistence(client);

		rpc.mockResolvedValueOnce({
			data: FILE_ID,
			error: null,
		});

		await persistence.abort({
			fileId: FILE_ID,
			reason: 'storage write failed',
		});

		expect(rpc).toHaveBeenCalledWith('abort_resource_file_upload', {
			file_id: FILE_ID,
			reason: 'storage write failed',
		});
	});

	it('records an unrecoverable storage failure through the failure RPC', async () => {
		const { client, rpc } = makeClient();
		const persistence = createSupabaseResourceUploadPersistence(client);

		rpc.mockResolvedValueOnce({
			data: FILE_ID,
			error: null,
		});

		await persistence.markFailed({
			fileId: FILE_ID,
			reason: 'compensating storage delete failed',
		});

		expect(rpc).toHaveBeenCalledWith('mark_resource_file_failed', {
			file_id: FILE_ID,
			reason: 'compensating storage delete failed',
		});
	});

	it('maps a rejected registration response to a safe deterministic reservation error', async () => {
		const { client, rpc } = makeClient();
		const persistence = createSupabaseResourceUploadPersistence(client);

		rpc.mockResolvedValueOnce({
			data: null,
			error: {
				message: `private failure involving ${RESOURCE_ID}`,
			},
		});

		const operation = persistence.reserve({
			resourceId: RESOURCE_ID,
			displayFilename: 'exam.pdf',
			contentType: 'application/pdf',
			byteSize: 1234,
			sha256: SHA256,
		});

		await expect(operation).rejects.toMatchObject({
			name: 'ResourceUploadPersistenceError',
			code: 'RESERVE_FAILED',
			message: 'Resource upload reservation failed',
		});
		await expect(operation).rejects.toBeInstanceOf(ResourceUploadPersistenceError);
		await expect(operation).rejects.not.toHaveProperty(
			'message',
			expect.stringContaining(RESOURCE_ID),
		);

		expect(rpc).toHaveBeenCalledTimes(1);
	});

	it('treats a thrown registration RPC as an unknown reservation outcome', async () => {
		const { client, rpc } = makeClient();
		const persistence = createSupabaseResourceUploadPersistence(client);

		rpc.mockRejectedValueOnce(new Error(`network failure involving ${RESOURCE_ID}`));

		const operation = persistence.reserve({
			resourceId: RESOURCE_ID,
			displayFilename: 'exam.pdf',
			contentType: 'application/pdf',
			byteSize: 1234,
			sha256: SHA256,
		});

		await expect(operation).rejects.toMatchObject({
			name: 'ResourceUploadPersistenceError',
			code: 'RESERVE_OUTCOME_UNKNOWN',
			message: 'Resource upload reservation outcome is unknown',
		});
		await expect(operation).rejects.not.toHaveProperty(
			'message',
			expect.stringContaining(RESOURCE_ID),
		);

		expect(rpc).toHaveBeenCalledTimes(1);
	});

	it('retries finalization once when the first RPC attempt throws', async () => {
		const { client, rpc } = makeClient();
		const persistence = createSupabaseResourceUploadPersistence(client);

		rpc.mockRejectedValueOnce(new Error('connection lost'));
		rpc.mockResolvedValueOnce({
			data: FILE_ID,
			error: null,
		});

		await expect(
			persistence.finalize({
				fileId: FILE_ID,
				sha256: SHA256,
			}),
		).resolves.toBeUndefined();

		expect(rpc).toHaveBeenCalledTimes(2);
		expect(rpc).toHaveBeenNthCalledWith(1, 'finalize_resource_file_upload', {
			file_id: FILE_ID,
			sha256: SHA256,
			comment: undefined,
		});
		expect(rpc).toHaveBeenNthCalledWith(2, 'finalize_resource_file_upload', {
			file_id: FILE_ID,
			sha256: SHA256,
			comment: undefined,
		});
	});

	it('does not retry a deterministic finalization RPC rejection', async () => {
		const { client, rpc } = makeClient();
		const persistence = createSupabaseResourceUploadPersistence(client);

		rpc.mockResolvedValueOnce({
			data: null,
			error: {
				message: 'database constraint failure',
			},
		});

		await expect(
			persistence.finalize({
				fileId: FILE_ID,
				sha256: SHA256,
			}),
		).rejects.toMatchObject({
			code: 'FINALIZE_FAILED',
			message: 'Resource upload finalization failed',
		});

		expect(rpc).toHaveBeenCalledTimes(1);
	});

	it('reports an unknown finalization outcome when both RPC attempts throw', async () => {
		const { client, rpc } = makeClient();
		const persistence = createSupabaseResourceUploadPersistence(client);

		rpc.mockRejectedValueOnce(new Error(`network failure involving ${FILE_ID}`));
		rpc.mockRejectedValueOnce(new Error(`retry failure involving ${FILE_ID}`));

		const operation = persistence.finalize({
			fileId: FILE_ID,
			sha256: SHA256,
		});

		await expect(operation).rejects.toMatchObject({
			name: 'ResourceUploadPersistenceError',
			code: 'FINALIZE_OUTCOME_UNKNOWN',
			message: 'Resource upload finalization outcome is unknown',
		});
		await expect(operation).rejects.not.toHaveProperty('message', expect.stringContaining(FILE_ID));

		expect(rpc).toHaveBeenCalledTimes(2);
	});

	it('reports an unknown outcome when the finalization retry returns an error', async () => {
		const { client, rpc } = makeClient();
		const persistence = createSupabaseResourceUploadPersistence(client);

		rpc.mockRejectedValueOnce(new Error('connection lost'));
		rpc.mockResolvedValueOnce({
			data: null,
			error: {
				message: 'retry could not determine final state',
			},
		});

		await expect(
			persistence.finalize({
				fileId: FILE_ID,
				sha256: SHA256,
			}),
		).rejects.toMatchObject({
			code: 'FINALIZE_OUTCOME_UNKNOWN',
			message: 'Resource upload finalization outcome is unknown',
		});

		expect(rpc).toHaveBeenCalledTimes(2);
	});

	it('rejects a null successful response from the abort RPC', async () => {
		const { client, rpc } = makeClient();
		const persistence = createSupabaseResourceUploadPersistence(client);

		rpc.mockResolvedValueOnce({
			data: null,
			error: null,
		});

		await expect(
			persistence.abort({
				fileId: FILE_ID,
			}),
		).rejects.toMatchObject({
			code: 'ABORT_FAILED',
			message: 'Resource upload abort failed',
		});
	});

	it('maps failure-recording errors independently from abort errors', async () => {
		const { client, rpc } = makeClient();
		const persistence = createSupabaseResourceUploadPersistence(client);

		rpc.mockResolvedValueOnce({
			data: null,
			error: {
				message: 'database failure',
			},
		});

		await expect(
			persistence.markFailed({
				fileId: FILE_ID,
			}),
		).rejects.toMatchObject({
			code: 'MARK_FAILED_FAILED',
			message: 'Resource upload failure recording failed',
		});
	});

	it('treats a status-zero registration response as an unknown reservation outcome', async () => {
		const { client, rpc } = makeClient();
		const persistence = createSupabaseResourceUploadPersistence(client);

		rpc.mockResolvedValueOnce({
			data: null,
			error: {
				message: 'TypeError: fetch failed',
			},
			status: 0,
			statusText: '',
		});

		await expect(
			persistence.reserve({
				resourceId: RESOURCE_ID,
				displayFilename: 'exam.pdf',
				contentType: 'application/pdf',
				byteSize: 1234,
				sha256: SHA256,
			}),
		).rejects.toMatchObject({
			code: 'RESERVE_OUTCOME_UNKNOWN',
			message: 'Resource upload reservation outcome is unknown',
		});

		expect(rpc).toHaveBeenCalledTimes(1);
	});

	it('finalizes the reservation through the atomic finalization RPC', async () => {
		const { client, rpc } = makeClient();
		const persistence = createSupabaseResourceUploadPersistence(client);

		rpc.mockResolvedValueOnce({
			data: FILE_ID,
			error: null,
			status: 200,
			statusText: 'OK',
		});

		await expect(
			persistence.finalize({
				fileId: FILE_ID,
				sha256: SHA256,
				comment: 'ready for review',
			}),
		).resolves.toBeUndefined();

		expect(rpc).toHaveBeenCalledTimes(1);
		expect(rpc).toHaveBeenCalledWith('finalize_resource_file_upload', {
			file_id: FILE_ID,
			sha256: SHA256,
			comment: 'ready for review',
		});
	});

	it('keeps finalization outcome unknown when status zero is followed by an HTTP error', async () => {
		const { client, rpc } = makeClient();
		const persistence = createSupabaseResourceUploadPersistence(client);

		rpc.mockResolvedValueOnce({
			data: null,
			error: {
				message: 'TypeError: fetch failed',
			},
			status: 0,
			statusText: '',
		});

		rpc.mockResolvedValueOnce({
			data: null,
			error: {
				message: 'resource is no longer editable',
			},
			status: 409,
			statusText: 'Conflict',
		});

		await expect(
			persistence.finalize({
				fileId: FILE_ID,
				sha256: SHA256,
			}),
		).rejects.toMatchObject({
			code: 'FINALIZE_OUTCOME_UNKNOWN',
			message: 'Resource upload finalization outcome is unknown',
		});

		expect(rpc).toHaveBeenCalledTimes(2);
	});
	it('treats a Cloudflare 520 registration response as an unknown reservation outcome', async () => {
		const { client, rpc } = makeClient();
		const persistence = createSupabaseResourceUploadPersistence(client);

		rpc.mockResolvedValueOnce({
			data: null,
			error: {
				message: 'Cloudflare connection error',
			},
			status: 520,
			statusText: 'Web Server Returned an Unknown Error',
		});

		await expect(
			persistence.reserve({
				resourceId: RESOURCE_ID,
				displayFilename: 'exam.pdf',
				contentType: 'application/pdf',
				byteSize: 1234,
				sha256: SHA256,
			}),
		).rejects.toMatchObject({
			code: 'RESERVE_OUTCOME_UNKNOWN',
			message: 'Resource upload reservation outcome is unknown',
		});

		expect(rpc).toHaveBeenCalledTimes(1);
	});
	it('retries finalization once after a Cloudflare 520 transport response', async () => {
		const { client, rpc } = makeClient();
		const persistence = createSupabaseResourceUploadPersistence(client);

		rpc.mockResolvedValueOnce({
			data: null,
			error: {
				message: 'Cloudflare connection error',
			},
			status: 520,
			statusText: 'Web Server Returned an Unknown Error',
		});

		rpc.mockResolvedValueOnce({
			data: FILE_ID,
			error: null,
			status: 200,
			statusText: 'OK',
		});

		await expect(
			persistence.finalize({
				fileId: FILE_ID,
				sha256: SHA256,
			}),
		).resolves.toBeUndefined();

		expect(rpc).toHaveBeenCalledTimes(2);
	});
});
