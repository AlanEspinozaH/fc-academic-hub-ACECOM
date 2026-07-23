import type { SupabaseServerClient } from './server';

export type ResourceUploadPersistenceErrorCode =
	| 'RESERVE_FAILED'
	| 'RESERVE_OUTCOME_UNKNOWN'
	| 'FINALIZE_FAILED'
	| 'FINALIZE_OUTCOME_UNKNOWN'
	| 'ABORT_FAILED'
	| 'MARK_FAILED_FAILED';

export class ResourceUploadPersistenceError extends Error {
	public readonly code: ResourceUploadPersistenceErrorCode;

	public constructor(code: ResourceUploadPersistenceErrorCode, message: string) {
		super(message);
		this.name = 'ResourceUploadPersistenceError';
		this.code = code;
	}
}

export interface ResourceUploadReservation {
	readonly resourceId: string;
	readonly displayFilename: string;
	readonly contentType: string;
	readonly byteSize: number;
	readonly sha256: string;
}

export interface ResourceUploadFinalization {
	readonly fileId: string;
	readonly sha256: string;
	readonly comment?: string;
}

export interface ResourceUploadAbort {
	readonly fileId: string;
	readonly reason?: string;
}

export interface ResourceUploadFailure {
	readonly fileId: string;
	readonly reason?: string;
}

export interface ResourceUploadPersistence {
	reserve(input: ResourceUploadReservation): Promise<string>;
	finalize(input: ResourceUploadFinalization): Promise<void>;
	abort(input: ResourceUploadAbort): Promise<void>;
	markFailed(input: ResourceUploadFailure): Promise<void>;
}

type ResourceUploadRpcClient = Pick<SupabaseServerClient, 'rpc'>;

const persistenceFailure = (
	code: ResourceUploadPersistenceErrorCode,
	message: string,
): ResourceUploadPersistenceError => new ResourceUploadPersistenceError(code, message);

const reservationOutcomeUnknown = (): ResourceUploadPersistenceError =>
	persistenceFailure('RESERVE_OUTCOME_UNKNOWN', 'Resource upload reservation outcome is unknown');

const finalizationOutcomeUnknown = (): ResourceUploadPersistenceError =>
	persistenceFailure('FINALIZE_OUTCOME_UNKNOWN', 'Resource upload finalization outcome is unknown');

const isUnknownTransportStatus = (status: number): boolean => status === 0 || status === 520;

export const createSupabaseResourceUploadPersistence = (
	client: ResourceUploadRpcClient,
): ResourceUploadPersistence =>
	Object.freeze({
		async reserve(input: ResourceUploadReservation): Promise<string> {
			try {
				const response = await client.rpc('register_resource_file_upload', {
					resource_id: input.resourceId,
					display_filename: input.displayFilename,
					content_type: input.contentType,
					byte_size: input.byteSize,
					sha256: input.sha256,
				});

				if (isUnknownTransportStatus(response.status)) {
					throw reservationOutcomeUnknown();
				}

				if (response.error !== null || response.data === null) {
					throw persistenceFailure('RESERVE_FAILED', 'Resource upload reservation failed');
				}

				return response.data;
			} catch (error) {
				if (error instanceof ResourceUploadPersistenceError) {
					throw error;
				}

				throw reservationOutcomeUnknown();
			}
		},

		async finalize(input: ResourceUploadFinalization): Promise<void> {
			const finalizeOnce = () =>
				client.rpc('finalize_resource_file_upload', {
					file_id: input.fileId,
					sha256: input.sha256,
					comment: input.comment,
				});

			let firstResponse;

			try {
				firstResponse = await finalizeOnce();
			} catch {
				firstResponse = null;
			}

			if (
				firstResponse !== null &&
				!isUnknownTransportStatus(firstResponse.status) &&
				firstResponse.error === null &&
				firstResponse.data !== null
			) {
				return;
			}

			if (
				firstResponse !== null &&
				!isUnknownTransportStatus(firstResponse.status) &&
				firstResponse.error !== null
			) {
				throw persistenceFailure('FINALIZE_FAILED', 'Resource upload finalization failed');
			}

			try {
				const retryResponse = await finalizeOnce();

				if (
					!isUnknownTransportStatus(retryResponse.status) &&
					retryResponse.error === null &&
					retryResponse.data !== null
				) {
					return;
				}

				throw finalizationOutcomeUnknown();
			} catch (error) {
				if (error instanceof ResourceUploadPersistenceError) {
					throw error;
				}

				throw finalizationOutcomeUnknown();
			}
		},

		async abort(input: ResourceUploadAbort): Promise<void> {
			try {
				const response = await client.rpc('abort_resource_file_upload', {
					file_id: input.fileId,
					reason: input.reason,
				});

				if (response.status === 0 || response.error !== null || response.data === null) {
					throw persistenceFailure('ABORT_FAILED', 'Resource upload abort failed');
				}
			} catch (error) {
				if (error instanceof ResourceUploadPersistenceError) {
					throw error;
				}

				throw persistenceFailure('ABORT_FAILED', 'Resource upload abort failed');
			}
		},

		async markFailed(input: ResourceUploadFailure): Promise<void> {
			try {
				const response = await client.rpc('mark_resource_file_failed', {
					file_id: input.fileId,
					reason: input.reason,
				});

				if (response.status === 0 || response.error !== null || response.data === null) {
					throw persistenceFailure(
						'MARK_FAILED_FAILED',
						'Resource upload failure recording failed',
					);
				}
			} catch (error) {
				if (error instanceof ResourceUploadPersistenceError) {
					throw error;
				}

				throw persistenceFailure('MARK_FAILED_FAILED', 'Resource upload failure recording failed');
			}
		},
	});
