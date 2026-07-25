export type ResourceStorageKeyVersion = 'legacy_pdf_v1' | 'generic_v2';

export const CURRENT_RESOURCE_STORAGE_KEY_VERSION = 'generic_v2' as const;

export type ResourceStorageKeyErrorCode =
	'INVALID_RESOURCE_ID' | 'INVALID_FILE_ID' | 'UNSUPPORTED_STORAGE_KEY_VERSION';

export class ResourceStorageKeyError extends Error {
	public readonly code: ResourceStorageKeyErrorCode;

	public constructor(code: ResourceStorageKeyErrorCode, message: string) {
		super(message);
		this.name = 'ResourceStorageKeyError';
		this.code = code;
	}
}

const UUID_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const canonicalizeUuid = (
	value: string,
	code: ResourceStorageKeyErrorCode,
	label: string,
): string => {
	const normalized = value.trim().toLowerCase();

	if (!UUID_PATTERN.test(normalized)) {
		throw new ResourceStorageKeyError(code, `${label} must be a canonical UUID`);
	}

	return normalized;
};

export const derivePrivateResourceStorageKey = (
	version: ResourceStorageKeyVersion,
	resourceId: string,
	fileId: string,
): string => {
	const canonicalResourceId = canonicalizeUuid(resourceId, 'INVALID_RESOURCE_ID', 'resource id');
	const canonicalFileId = canonicalizeUuid(fileId, 'INVALID_FILE_ID', 'file id');
	const baseKey = `resources/${canonicalResourceId}/${canonicalFileId}`;

	if (version === 'legacy_pdf_v1') {
		return `${baseKey}.pdf`;
	}

	if (version === 'generic_v2') {
		return baseKey;
	}

	throw new ResourceStorageKeyError(
		'UNSUPPORTED_STORAGE_KEY_VERSION',
		'unsupported resource storage key version',
	);
};
