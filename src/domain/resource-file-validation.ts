export const RESOURCE_PDF_CONTENT_TYPE = 'application/pdf' as const;
export const RESOURCE_PDF_MAX_BYTES = 10_000_000;

const PDF_HEADER = new Uint8Array([0x25, 0x50, 0x44, 0x46, 0x2d]);
const PDF_EOF_MARKER = new Uint8Array([0x25, 0x25, 0x45, 0x4f, 0x46]);
const PDF_EOF_SEARCH_WINDOW_BYTES = 1_024;
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

export interface ResourceFileCandidate {
	readonly bytes: Uint8Array;
	readonly contentType: string;
	readonly filename: string;
}

export interface ValidatedResourcePdf {
	readonly bytes: Uint8Array;
	readonly byteSize: number;
	readonly contentType: typeof RESOURCE_PDF_CONTENT_TYPE;
	readonly filename: string;
	readonly sha256: string;
}

export type ResourcePdfValidationErrorCode =
	| 'EMPTY_FILE'
	| 'FILE_TOO_LARGE'
	| 'INVALID_CONTENT_TYPE'
	| 'INVALID_FILENAME'
	| 'INVALID_PDF_HEADER'
	| 'INVALID_PDF_TRAILER'
	| 'MISSING_FILENAME'
	| 'WRONG_FILE_EXTENSION';

export class ResourcePdfValidationError extends Error {
	public readonly code: ResourcePdfValidationErrorCode;

	public constructor(code: ResourcePdfValidationErrorCode, message: string) {
		super(message);
		this.name = 'ResourcePdfValidationError';
		this.code = code;
	}
}

const fail = (code: ResourcePdfValidationErrorCode, message: string): never => {
	throw new ResourcePdfValidationError(code, message);
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

export const validateResourcePdf = async (
	candidate: ResourceFileCandidate,
): Promise<ValidatedResourcePdf> => {
	const filename = candidate.filename.trim();

	if (filename.length === 0) {
		fail('MISSING_FILENAME', 'resource PDF filename is required');
	}

	if (hasUnsafeFilenameCharacters(filename)) {
		fail('INVALID_FILENAME', 'resource PDF filename must be a basename without control characters');
	}

	const lowercaseFilename = filename.toLowerCase();

	if (!lowercaseFilename.endsWith('.pdf') || lowercaseFilename === '.pdf') {
		fail('WRONG_FILE_EXTENSION', 'resource PDF filename must end with .pdf');
	}

	const contentType = candidate.contentType.trim().toLowerCase();

	if (contentType !== RESOURCE_PDF_CONTENT_TYPE) {
		fail('INVALID_CONTENT_TYPE', 'resource PDF content type must be application/pdf');
	}

	const byteSize = candidate.bytes.byteLength;

	if (byteSize === 0) {
		fail('EMPTY_FILE', 'resource PDF cannot be empty');
	}

	if (byteSize > RESOURCE_PDF_MAX_BYTES) {
		fail('FILE_TOO_LARGE', `resource PDF cannot exceed ${RESOURCE_PDF_MAX_BYTES} bytes`);
	}

	// Copy before structural validation and hashing so the result is based on a
	// stable snapshot rather than a caller-owned mutable view.
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
		filename,
		sha256: toLowercaseHex(digest),
	});
};
