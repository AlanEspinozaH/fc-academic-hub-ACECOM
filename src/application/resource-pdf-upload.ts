import {
	validateResourcePdf,
	type ResourceFileCandidate,
} from '../domain/resource-file-validation';
import type { ResourceObjectStore } from '../infrastructure/r2/resource-object-store';
import { derivePrivateResourceStorageKey } from '../infrastructure/r2/resource-storage-key';
import {
	ResourceUploadPersistenceError,
	type ResourceUploadPersistence,
} from '../infrastructure/supabase/resource-upload-persistence';

export type ResourcePdfUploadErrorCode =
	| 'RESERVATION_FAILED'
	| 'RESERVATION_OUTCOME_UNKNOWN'
	| 'STORAGE_KEY_FAILED'
	| 'STORAGE_WRITE_FAILED'
	| 'FINALIZATION_FAILED'
	| 'FINALIZATION_OUTCOME_UNKNOWN'
	| 'COMPENSATION_FAILED';

export class ResourcePdfUploadError extends Error {
	public readonly code: ResourcePdfUploadErrorCode;

	public constructor(code: ResourcePdfUploadErrorCode, message: string) {
		super(message);
		this.name = 'ResourcePdfUploadError';
		this.code = code;
	}
}

export interface ResourcePdfUploadInput {
	readonly resourceId: string;
	readonly candidate: ResourceFileCandidate;
	readonly comment?: string;
}

export interface ResourcePdfUploadResult {
	readonly fileId: string;
}

export interface ResourcePdfUploadOrchestrator {
	upload(input: ResourcePdfUploadInput): Promise<ResourcePdfUploadResult>;
}

const uploadFailure = (code: ResourcePdfUploadErrorCode, message: string): ResourcePdfUploadError =>
	new ResourcePdfUploadError(code, message);

const compensationFailed = (): ResourcePdfUploadError =>
	uploadFailure('COMPENSATION_FAILED', 'Resource upload compensation failed');

const isPersistenceError = (
	error: unknown,
	code: ResourceUploadPersistenceError['code'],
): boolean => error instanceof ResourceUploadPersistenceError && error.code === code;

export const createResourcePdfUploadOrchestrator = (
	persistence: ResourceUploadPersistence,
	objectStore: ResourceObjectStore,
): ResourcePdfUploadOrchestrator =>
	Object.freeze({
		async upload(input: ResourcePdfUploadInput): Promise<ResourcePdfUploadResult> {
			const validatedPdf = await validateResourcePdf(input.candidate);

			let fileId: string;

			try {
				fileId = await persistence.reserve({
					resourceId: input.resourceId,
					displayFilename: validatedPdf.filename,
					contentType: validatedPdf.contentType,
					byteSize: validatedPdf.byteSize,
					sha256: validatedPdf.sha256,
				});
			} catch (error) {
				if (isPersistenceError(error, 'RESERVE_FAILED')) {
					throw uploadFailure('RESERVATION_FAILED', 'Resource upload reservation failed');
				}

				throw uploadFailure(
					'RESERVATION_OUTCOME_UNKNOWN',
					'Resource upload reservation outcome is unknown',
				);
			}

			let storageKey: string;

			try {
				storageKey = derivePrivateResourceStorageKey(input.resourceId, fileId);
			} catch {
				try {
					await persistence.abort({
						fileId,
						reason: 'storage key derivation failed',
					});
				} catch {
					throw compensationFailed();
				}

				throw uploadFailure('STORAGE_KEY_FAILED', 'Private resource storage key derivation failed');
			}

			try {
				await objectStore.write({
					storageKey,
					bytes: validatedPdf.bytes,
					contentType: validatedPdf.contentType,
				});
			} catch {
				try {
					await objectStore.delete(storageKey);
				} catch {
					throw compensationFailed();
				}

				try {
					await persistence.abort({
						fileId,
						reason: 'storage write failed',
					});
				} catch {
					throw compensationFailed();
				}

				throw uploadFailure('STORAGE_WRITE_FAILED', 'Private resource object write failed');
			}

			try {
				await persistence.finalize({
					fileId,
					sha256: validatedPdf.sha256,
					comment: input.comment,
				});
			} catch (error) {
				if (!isPersistenceError(error, 'FINALIZE_FAILED')) {
					throw uploadFailure(
						'FINALIZATION_OUTCOME_UNKNOWN',
						'Resource upload finalization outcome is unknown',
					);
				}

				try {
					await objectStore.delete(storageKey);
				} catch {
					try {
						await persistence.markFailed({
							fileId,
							reason: 'compensating storage delete failed',
						});
					} catch {
						throw compensationFailed();
					}

					throw uploadFailure('FINALIZATION_FAILED', 'Resource upload finalization failed');
				}

				try {
					await persistence.abort({
						fileId,
						reason: 'resource upload finalization failed',
					});
				} catch {
					throw compensationFailed();
				}

				throw uploadFailure('FINALIZATION_FAILED', 'Resource upload finalization failed');
			}

			return Object.freeze({
				fileId,
			});
		},
	});
