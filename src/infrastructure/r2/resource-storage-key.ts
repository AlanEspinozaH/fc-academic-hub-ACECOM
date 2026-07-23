export type ResourceStorageKeyErrorCode = 'INVALID_RESOURCE_ID' | 'INVALID_FILE_ID';

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

export const derivePrivateResourceStorageKey = (resourceId: string, fileId: string): string => {
	const canonicalResourceId = canonicalizeUuid(resourceId, 'INVALID_RESOURCE_ID', 'resource id');
	const canonicalFileId = canonicalizeUuid(fileId, 'INVALID_FILE_ID', 'file id');

	return `resources/${canonicalResourceId}/${canonicalFileId}.pdf`;
};
