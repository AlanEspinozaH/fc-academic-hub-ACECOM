import { describe, expect, it, vi } from 'vitest';
import type { ResourceObjectStore } from '../infrastructure/r2/resource-object-store';
import {
	ResourceUploadPersistenceError,
	type ResourceUploadPersistence,
} from '../infrastructure/supabase/resource-upload-persistence';
import { ResourcePdfUploadError, createResourcePdfUploadOrchestrator } from './resource-pdf-upload';

const RESOURCE_ID = '11111111-2222-3333-4444-555555555555';
const FILE_ID = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee';
const STORAGE_KEY = `resources/${RESOURCE_ID}/${FILE_ID}.pdf`;
const SHA256 = '1e7313ace78f0fb481a486939b4885902663102818090805515553d84e0bbfd3';

const makeCandidate = () => ({
	filename: 'exam.pdf',
	contentType: 'application/pdf',
	bytes: new TextEncoder().encode('%PDF-1.7\n%%EOF\n'),
});

const makeDependencies = () => {
	const reserve = vi.fn(async (): Promise<string> => FILE_ID);
	const finalize = vi.fn(async (): Promise<void> => undefined);
	const abort = vi.fn(async (): Promise<void> => undefined);
	const markFailed = vi.fn(async (): Promise<void> => undefined);

	const persistence = {
		reserve,
		finalize,
		abort,
		markFailed,
	} as unknown as ResourceUploadPersistence;

	const write = vi.fn(async (): Promise<void> => undefined);
	const deleteObject = vi.fn(async (): Promise<void> => undefined);

	const objectStore = {
		write,
		delete: deleteObject,
	} as unknown as ResourceObjectStore;

	return {
		persistence,
		objectStore,
		reserve,
		finalize,
		abort,
		markFailed,
		write,
		deleteObject,
	};
};

describe('resource PDF upload orchestrator', () => {
	it('validates, reserves, writes and finalizes a private PDF', async () => {
		const dependencies = makeDependencies();
		const orchestrator = createResourcePdfUploadOrchestrator(
			dependencies.persistence,
			dependencies.objectStore,
		);

		const result = await orchestrator.upload({
			resourceId: RESOURCE_ID,
			candidate: makeCandidate(),
			comment: 'ready for review',
		});

		expect(result).toEqual({
			fileId: FILE_ID,
		});

		expect(dependencies.reserve).toHaveBeenCalledWith({
			resourceId: RESOURCE_ID,
			displayFilename: 'exam.pdf',
			contentType: 'application/pdf',
			byteSize: 15,
			sha256: SHA256,
		});

		expect(dependencies.write).toHaveBeenCalledWith({
			storageKey: STORAGE_KEY,
			bytes: expect.any(Uint8Array),
			contentType: 'application/pdf',
		});

		expect(dependencies.finalize).toHaveBeenCalledWith({
			fileId: FILE_ID,
			sha256: SHA256,
			comment: 'ready for review',
		});

		expect(dependencies.abort).not.toHaveBeenCalled();
		expect(dependencies.markFailed).not.toHaveBeenCalled();
		expect(dependencies.deleteObject).not.toHaveBeenCalled();
	});

	it('does not reserve or write when PDF validation fails', async () => {
		const dependencies = makeDependencies();
		const orchestrator = createResourcePdfUploadOrchestrator(
			dependencies.persistence,
			dependencies.objectStore,
		);

		await expect(
			orchestrator.upload({
				resourceId: RESOURCE_ID,
				candidate: {
					filename: 'exam.pdf',
					contentType: 'application/pdf',
					bytes: new TextEncoder().encode('not a PDF'),
				},
			}),
		).rejects.toMatchObject({
			code: 'INVALID_PDF_HEADER',
		});

		expect(dependencies.reserve).not.toHaveBeenCalled();
		expect(dependencies.write).not.toHaveBeenCalled();
	});

	it('stops before R2 when reservation deterministically fails', async () => {
		const dependencies = makeDependencies();

		dependencies.reserve.mockRejectedValueOnce(
			new ResourceUploadPersistenceError('RESERVE_FAILED', 'Resource upload reservation failed'),
		);

		const orchestrator = createResourcePdfUploadOrchestrator(
			dependencies.persistence,
			dependencies.objectStore,
		);

		await expect(
			orchestrator.upload({
				resourceId: RESOURCE_ID,
				candidate: makeCandidate(),
			}),
		).rejects.toMatchObject({
			code: 'RESERVATION_FAILED',
		});

		expect(dependencies.write).not.toHaveBeenCalled();
		expect(dependencies.abort).not.toHaveBeenCalled();
	});

	it('preserves state when reservation outcome is unknown', async () => {
		const dependencies = makeDependencies();

		dependencies.reserve.mockRejectedValueOnce(
			new ResourceUploadPersistenceError(
				'RESERVE_OUTCOME_UNKNOWN',
				'Resource upload reservation outcome is unknown',
			),
		);

		const orchestrator = createResourcePdfUploadOrchestrator(
			dependencies.persistence,
			dependencies.objectStore,
		);

		await expect(
			orchestrator.upload({
				resourceId: RESOURCE_ID,
				candidate: makeCandidate(),
			}),
		).rejects.toMatchObject({
			code: 'RESERVATION_OUTCOME_UNKNOWN',
		});

		expect(dependencies.write).not.toHaveBeenCalled();
		expect(dependencies.abort).not.toHaveBeenCalled();
	});

	it('aborts the reservation when storage-key derivation fails', async () => {
		const dependencies = makeDependencies();

		const orchestrator = createResourcePdfUploadOrchestrator(
			dependencies.persistence,
			dependencies.objectStore,
		);

		await expect(
			orchestrator.upload({
				resourceId: 'resource-id-accepted-by-test-double',
				candidate: makeCandidate(),
			}),
		).rejects.toMatchObject({
			code: 'STORAGE_KEY_FAILED',
		});

		expect(dependencies.abort).toHaveBeenCalledWith({
			fileId: FILE_ID,
			reason: 'storage key derivation failed',
		});
		expect(dependencies.write).not.toHaveBeenCalled();
	});

	it('deletes the storage key and aborts the reservation when R2 write fails', async () => {
		const dependencies = makeDependencies();
		dependencies.write.mockRejectedValueOnce(new Error('R2 write failure'));

		const orchestrator = createResourcePdfUploadOrchestrator(
			dependencies.persistence,
			dependencies.objectStore,
		);

		await expect(
			orchestrator.upload({
				resourceId: RESOURCE_ID,
				candidate: makeCandidate(),
			}),
		).rejects.toMatchObject({
			code: 'STORAGE_WRITE_FAILED',
		});

		expect(dependencies.deleteObject).toHaveBeenCalledWith(STORAGE_KEY);
		expect(dependencies.abort).toHaveBeenCalledWith({
			fileId: FILE_ID,
			reason: 'storage write failed',
		});
		expect(dependencies.finalize).not.toHaveBeenCalled();
		expect(dependencies.markFailed).not.toHaveBeenCalled();
	});

	it('preserves the reservation when cleanup after an R2 write failure also fails', async () => {
		const dependencies = makeDependencies();
		dependencies.write.mockRejectedValueOnce(new Error('R2 write failure'));
		dependencies.deleteObject.mockRejectedValueOnce(new Error('R2 delete failure'));

		const orchestrator = createResourcePdfUploadOrchestrator(
			dependencies.persistence,
			dependencies.objectStore,
		);

		await expect(
			orchestrator.upload({
				resourceId: RESOURCE_ID,
				candidate: makeCandidate(),
			}),
		).rejects.toMatchObject({
			code: 'COMPENSATION_FAILED',
		});

		expect(dependencies.abort).not.toHaveBeenCalled();
		expect(dependencies.markFailed).not.toHaveBeenCalled();
	});

	it('reports compensation failure when aborting after a cleaned R2 write failure fails', async () => {
		const dependencies = makeDependencies();
		dependencies.write.mockRejectedValueOnce(new Error('R2 write failure'));
		dependencies.abort.mockRejectedValueOnce(new Error('abort failure'));

		const orchestrator = createResourcePdfUploadOrchestrator(
			dependencies.persistence,
			dependencies.objectStore,
		);

		await expect(
			orchestrator.upload({
				resourceId: RESOURCE_ID,
				candidate: makeCandidate(),
			}),
		).rejects.toMatchObject({
			code: 'COMPENSATION_FAILED',
		});

		expect(dependencies.deleteObject).toHaveBeenCalledWith(STORAGE_KEY);
	});

	it('deletes R2 and aborts metadata when finalization deterministically fails', async () => {
		const dependencies = makeDependencies();

		dependencies.finalize.mockRejectedValueOnce(
			new ResourceUploadPersistenceError('FINALIZE_FAILED', 'Resource upload finalization failed'),
		);

		const orchestrator = createResourcePdfUploadOrchestrator(
			dependencies.persistence,
			dependencies.objectStore,
		);

		await expect(
			orchestrator.upload({
				resourceId: RESOURCE_ID,
				candidate: makeCandidate(),
			}),
		).rejects.toMatchObject({
			code: 'FINALIZATION_FAILED',
		});

		expect(dependencies.deleteObject).toHaveBeenCalledWith(STORAGE_KEY);
		expect(dependencies.abort).toHaveBeenCalledWith({
			fileId: FILE_ID,
			reason: 'resource upload finalization failed',
		});
		expect(dependencies.markFailed).not.toHaveBeenCalled();
	});

	it('does not delete R2 when finalization outcome is unknown', async () => {
		const dependencies = makeDependencies();

		dependencies.finalize.mockRejectedValueOnce(
			new ResourceUploadPersistenceError(
				'FINALIZE_OUTCOME_UNKNOWN',
				'Resource upload finalization outcome is unknown',
			),
		);

		const orchestrator = createResourcePdfUploadOrchestrator(
			dependencies.persistence,
			dependencies.objectStore,
		);

		await expect(
			orchestrator.upload({
				resourceId: RESOURCE_ID,
				candidate: makeCandidate(),
			}),
		).rejects.toMatchObject({
			code: 'FINALIZATION_OUTCOME_UNKNOWN',
		});

		expect(dependencies.deleteObject).not.toHaveBeenCalled();
		expect(dependencies.abort).not.toHaveBeenCalled();
		expect(dependencies.markFailed).not.toHaveBeenCalled();
	});

	it('marks storage failed when finalization and compensating delete both fail', async () => {
		const dependencies = makeDependencies();

		dependencies.finalize.mockRejectedValueOnce(
			new ResourceUploadPersistenceError('FINALIZE_FAILED', 'Resource upload finalization failed'),
		);
		dependencies.deleteObject.mockRejectedValueOnce(new Error('delete failure'));

		const orchestrator = createResourcePdfUploadOrchestrator(
			dependencies.persistence,
			dependencies.objectStore,
		);

		await expect(
			orchestrator.upload({
				resourceId: RESOURCE_ID,
				candidate: makeCandidate(),
			}),
		).rejects.toMatchObject({
			code: 'FINALIZATION_FAILED',
		});

		expect(dependencies.markFailed).toHaveBeenCalledWith({
			fileId: FILE_ID,
			reason: 'compensating storage delete failed',
		});
		expect(dependencies.abort).not.toHaveBeenCalled();
	});

	it('reports compensation failure when delete and failure recording both fail', async () => {
		const dependencies = makeDependencies();

		dependencies.finalize.mockRejectedValueOnce(
			new ResourceUploadPersistenceError('FINALIZE_FAILED', 'Resource upload finalization failed'),
		);
		dependencies.deleteObject.mockRejectedValueOnce(new Error('delete failure'));
		dependencies.markFailed.mockRejectedValueOnce(new Error('mark failed failure'));

		const orchestrator = createResourcePdfUploadOrchestrator(
			dependencies.persistence,
			dependencies.objectStore,
		);

		const operation = orchestrator.upload({
			resourceId: RESOURCE_ID,
			candidate: makeCandidate(),
		});

		await expect(operation).rejects.toMatchObject({
			name: 'ResourcePdfUploadError',
			code: 'COMPENSATION_FAILED',
			message: 'Resource upload compensation failed',
		});

		await expect(operation).rejects.toBeInstanceOf(ResourcePdfUploadError);
	});

	it('reports compensation failure when metadata abort fails after a successful delete', async () => {
		const dependencies = makeDependencies();

		dependencies.finalize.mockRejectedValueOnce(
			new ResourceUploadPersistenceError('FINALIZE_FAILED', 'Resource upload finalization failed'),
		);
		dependencies.abort.mockRejectedValueOnce(new Error('abort failure'));

		const orchestrator = createResourcePdfUploadOrchestrator(
			dependencies.persistence,
			dependencies.objectStore,
		);

		await expect(
			orchestrator.upload({
				resourceId: RESOURCE_ID,
				candidate: makeCandidate(),
			}),
		).rejects.toMatchObject({
			code: 'COMPENSATION_FAILED',
		});

		expect(dependencies.deleteObject).toHaveBeenCalledWith(STORAGE_KEY);
		expect(dependencies.markFailed).not.toHaveBeenCalled();
	});
});
