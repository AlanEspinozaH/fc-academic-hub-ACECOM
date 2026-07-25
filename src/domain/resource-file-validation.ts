export const RESOURCE_FILE_MAX_BYTES = 10_000_000;
export const RESOURCE_PDF_CONTENT_TYPE = 'application/pdf' as const;
export const RESOURCE_PDF_FILE_KIND = 'pdf' as const;
export const RESOURCE_PDF_NORMALIZED_EXTENSION = '.pdf' as const;

export type ResourceFileKind = 'pdf' | 'image' | 'markdown' | 'tex' | 'text' | 'source';

export interface ResourceFileCandidate {
	readonly bytes: Uint8Array;
	readonly declaredContentType: string;
	readonly filename: string;
}

export interface ValidatedResourceFile {
	readonly bytes: Uint8Array<ArrayBuffer>;
	readonly byteSize: number;
	readonly contentType: string;
	readonly fileKind: ResourceFileKind;
	readonly filename: string;
	readonly normalizedExtension: string;
	readonly sha256: string;
}

export type ResourceFileValidationErrorCode =
	| 'EMPTY_FILE'
	| 'FILE_TOO_LARGE'
	| 'INVALID_FILENAME'
	| 'INVALID_PDF_HEADER'
	| 'INVALID_PDF_TRAILER'
	| 'MISSING_FILENAME'
	| 'UNSUPPORTED_FILE_TYPE';

export class ResourceFileValidationError extends Error {
	public readonly code: ResourceFileValidationErrorCode;

	public constructor(code: ResourceFileValidationErrorCode, message: string) {
		super(message);
		this.name = 'ResourceFileValidationError';
		this.code = code;
	}
}

const PDF_HEADER = new Uint8Array([0x25, 0x50, 0x44, 0x46, 0x2d]);
const PDF_EOF_MARKER = new Uint8Array([0x25, 0x25, 0x45, 0x4f, 0x46]);
const PDF_EOF_SEARCH_WINDOW_BYTES = 1_024;

const fail = (code: ResourceFileValidationErrorCode, message: string): never => {
	throw new ResourceFileValidationError(code, message);
};

const hasUnsafeFilenameCharacters = (filename: string): boolean => {
	for (let index = 0; index < filename.length; index += 1) {
		const codeUnit = filename.charCodeAt(index);
		const isControlCharacter = codeUnit <= 0x1f || codeUnit === 0x7f;
		const isPathSeparator = codeUnit === 0x2f || codeUnit === 0x5c;

		if (isControlCharacter || isPathSeparator) {
			return true;
		}
	}

	return false;
};

const normalizeFilename = (candidateFilename: string): string => {
	const filename = candidateFilename.trim();

	if (filename.length === 0) {
		fail('MISSING_FILENAME', 'resource file filename is required');
	}

	if (hasUnsafeFilenameCharacters(filename)) {
		fail('INVALID_FILENAME', 'resource file filename must be a safe basename');
	}

	if (filename === '.' || filename === '..' || filename.toLowerCase() === '.pdf') {
		fail('INVALID_FILENAME', 'resource file filename must include a basename');
	}

	return filename;
};

const normalizedExtensionOf = (filename: string): string => {
	const extensionOffset = filename.lastIndexOf('.');

	if (extensionOffset <= 0 || extensionOffset === filename.length - 1) {
		return '';
	}

	return filename.slice(extensionOffset).toLowerCase();
};

const hasSequenceAt = (bytes: Uint8Array, sequence: Uint8Array, offset: number): boolean => {
	if (offset < 0 || offset + sequence.length > bytes.length) {
		return false;
	}

	for (let index = 0; index < sequence.length; index += 1) {
		if (bytes[offset + index] !== sequence[index]) {
			return false;
		}
	}

	return true;
};

const isPdfWhitespace = (byte: number): boolean =>
	byte === 0x00 ||
	byte === 0x09 ||
	byte === 0x0a ||
	byte === 0x0c ||
	byte === 0x0d ||
	byte === 0x20;

const hasValidPdfTrailer = (bytes: Uint8Array): boolean => {
	const firstSearchOffset = Math.max(0, bytes.length - PDF_EOF_SEARCH_WINDOW_BYTES);

	for (
		let offset = bytes.length - PDF_EOF_MARKER.length;
		offset >= firstSearchOffset;
		offset -= 1
	) {
		if (!hasSequenceAt(bytes, PDF_EOF_MARKER, offset)) {
			continue;
		}

		for (
			let trailingOffset = offset + PDF_EOF_MARKER.length;
			trailingOffset < bytes.length;
			trailingOffset += 1
		) {
			if (!isPdfWhitespace(bytes[trailingOffset])) {
				return false;
			}
		}

		return true;
	}

	return false;
};

const toLowercaseHex = (buffer: ArrayBuffer): string =>
	Array.from(new Uint8Array(buffer), (byte) => byte.toString(16).padStart(2, '0')).join('');

const validatePdf = async (
	candidate: ResourceFileCandidate,
	filename: string,
): Promise<ValidatedResourceFile> => {
	const byteSize = candidate.bytes.byteLength;

	if (byteSize === 0) {
		fail('EMPTY_FILE', 'resource file cannot be empty');
	}

	if (byteSize > RESOURCE_FILE_MAX_BYTES) {
		fail('FILE_TOO_LARGE', `resource PDF cannot exceed ${RESOURCE_FILE_MAX_BYTES} bytes`);
	}

	// Snapshot caller-owned bytes before structural validation and hashing.
	const bytes: Uint8Array<ArrayBuffer> = Uint8Array.from(candidate.bytes);

	if (!hasSequenceAt(bytes, PDF_HEADER, 0)) {
		fail('INVALID_PDF_HEADER', 'resource file must begin with the %PDF- signature');
	}

	if (!hasValidPdfTrailer(bytes)) {
		fail('INVALID_PDF_TRAILER', 'resource PDF must end with a valid %%EOF marker');
	}

	const digest = await globalThis.crypto.subtle.digest('SHA-256', bytes);

	return Object.freeze({
		bytes,
		byteSize,
		contentType: RESOURCE_PDF_CONTENT_TYPE,
		fileKind: RESOURCE_PDF_FILE_KIND,
		filename,
		normalizedExtension: RESOURCE_PDF_NORMALIZED_EXTENSION,
		sha256: toLowercaseHex(digest),
	});
};

export const validateResourceFile = async (
	candidate: ResourceFileCandidate,
): Promise<ValidatedResourceFile> => {
	const filename = normalizeFilename(candidate.filename);
	const normalizedExtension = normalizedExtensionOf(filename);

	if (normalizedExtension === RESOURCE_PDF_NORMALIZED_EXTENSION) {
		return validatePdf(candidate, filename);
	}

	return fail('UNSUPPORTED_FILE_TYPE', 'submitted file type is not currently supported');
};
