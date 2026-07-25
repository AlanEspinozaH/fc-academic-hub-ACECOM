export const RESOURCE_FILE_MAX_BYTES = 10_000_000;
export const RESOURCE_TEXT_MAX_BYTES = 2_000_000;
export const RESOURCE_PDF_CONTENT_TYPE = 'application/pdf' as const;
export const RESOURCE_PDF_FILE_KIND = 'pdf' as const;
export const RESOURCE_PDF_NORMALIZED_EXTENSION = '.pdf' as const;
export const RESOURCE_PNG_CONTENT_TYPE = 'image/png' as const;
export const RESOURCE_PNG_NORMALIZED_EXTENSION = '.png' as const;
export const RESOURCE_JPEG_CONTENT_TYPE = 'image/jpeg' as const;
export const RESOURCE_JPEG_NORMALIZED_EXTENSIONS = ['.jpg', '.jpeg'] as const;
export const RESOURCE_IMAGE_FILE_KIND = 'image' as const;
export const RESOURCE_TEXT_CONTENT_TYPE = 'text/plain' as const;
export const RESOURCE_MARKDOWN_NORMALIZED_EXTENSION = '.md' as const;
export const RESOURCE_TEX_NORMALIZED_EXTENSION = '.tex' as const;
export const RESOURCE_PLAIN_TEXT_NORMALIZED_EXTENSION = '.txt' as const;
export const RESOURCE_SOURCE_NORMALIZED_EXTENSIONS = [
	'.java',
	'.py',
	'.c',
	'.h',
	'.cpp',
	'.hpp',
	'.js',
	'.ts',
	'.rs',
	'.go',
	'.sql',
	'.sh',
] as const;

export type ResourceSourceNormalizedExtension =
	(typeof RESOURCE_SOURCE_NORMALIZED_EXTENSIONS)[number];

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
	| 'INVALID_JPEG_SIGNATURE'
	| 'INVALID_PDF_HEADER'
	| 'INVALID_PDF_TRAILER'
	| 'INVALID_PNG_SIGNATURE'
	| 'INVALID_UTF8_TEXT'
	| 'MISSING_FILENAME'
	| 'TEXT_CONTAINS_NUL'
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
const PNG_SIGNATURE = new Uint8Array([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const REGISTERED_EXTENSION_ONLY_FILENAMES = new Set<string>([
	RESOURCE_PDF_NORMALIZED_EXTENSION,
	RESOURCE_PNG_NORMALIZED_EXTENSION,
	...RESOURCE_JPEG_NORMALIZED_EXTENSIONS,
	RESOURCE_MARKDOWN_NORMALIZED_EXTENSION,
	RESOURCE_TEX_NORMALIZED_EXTENSION,
	RESOURCE_PLAIN_TEXT_NORMALIZED_EXTENSION,
	...RESOURCE_SOURCE_NORMALIZED_EXTENSIONS,
]);
const SOURCE_EXTENSION_SET = new Set<string>(RESOURCE_SOURCE_NORMALIZED_EXTENSIONS);
const isResourceSourceNormalizedExtension = (
	value: string,
): value is ResourceSourceNormalizedExtension => SOURCE_EXTENSION_SET.has(value);

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

	if (
		filename === '.' ||
		filename === '..' ||
		REGISTERED_EXTENSION_ONLY_FILENAMES.has(filename.toLowerCase())
	) {
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

const snapshotCandidateBytes = (
	candidate: ResourceFileCandidate,
	formatLabel: string,
	maximumBytes = RESOURCE_FILE_MAX_BYTES,
): Uint8Array<ArrayBuffer> => {
	const byteSize = candidate.bytes.byteLength;

	if (byteSize === 0) {
		fail('EMPTY_FILE', 'resource file cannot be empty');
	}

	if (byteSize > maximumBytes) {
		fail('FILE_TOO_LARGE', `resource ${formatLabel} cannot exceed ${maximumBytes} bytes`);
	}

	return Uint8Array.from(candidate.bytes);
};

const sha256 = async (bytes: Uint8Array<ArrayBuffer>): Promise<string> => {
	const digest = await globalThis.crypto.subtle.digest('SHA-256', bytes);

	return toLowercaseHex(digest);
};

const validateText = async (
	candidate: ResourceFileCandidate,
	filename: string,
	fileKind: Extract<ResourceFileKind, 'markdown' | 'tex' | 'text' | 'source'>,
	normalizedExtension:
		| typeof RESOURCE_MARKDOWN_NORMALIZED_EXTENSION
		| typeof RESOURCE_TEX_NORMALIZED_EXTENSION
		| typeof RESOURCE_PLAIN_TEXT_NORMALIZED_EXTENSION
		| ResourceSourceNormalizedExtension,
): Promise<ValidatedResourceFile> => {
	const byteSize = candidate.bytes.byteLength;
	const bytes = snapshotCandidateBytes(candidate, 'text file', RESOURCE_TEXT_MAX_BYTES);

	if (bytes.includes(0x00)) {
		fail('TEXT_CONTAINS_NUL', 'resource text file cannot contain NUL bytes');
	}

	try {
		new TextDecoder('utf-8', { fatal: true }).decode(bytes);
	} catch {
		fail('INVALID_UTF8_TEXT', 'resource text file must contain valid UTF-8');
	}

	return Object.freeze({
		bytes,
		byteSize,
		contentType: RESOURCE_TEXT_CONTENT_TYPE,
		fileKind,
		filename,
		normalizedExtension,
		sha256: await sha256(bytes),
	});
};

const validatePdf = async (
	candidate: ResourceFileCandidate,
	filename: string,
): Promise<ValidatedResourceFile> => {
	const byteSize = candidate.bytes.byteLength;
	const bytes = snapshotCandidateBytes(candidate, 'PDF');

	if (!hasSequenceAt(bytes, PDF_HEADER, 0)) {
		fail('INVALID_PDF_HEADER', 'resource file must begin with the %PDF- signature');
	}

	if (!hasValidPdfTrailer(bytes)) {
		fail('INVALID_PDF_TRAILER', 'resource PDF must end with a valid %%EOF marker');
	}

	return Object.freeze({
		bytes,
		byteSize,
		contentType: RESOURCE_PDF_CONTENT_TYPE,
		fileKind: RESOURCE_PDF_FILE_KIND,
		filename,
		normalizedExtension: RESOURCE_PDF_NORMALIZED_EXTENSION,
		sha256: await sha256(bytes),
	});
};

const validatePng = async (
	candidate: ResourceFileCandidate,
	filename: string,
): Promise<ValidatedResourceFile> => {
	const byteSize = candidate.bytes.byteLength;
	const bytes = snapshotCandidateBytes(candidate, 'PNG');

	if (!hasSequenceAt(bytes, PNG_SIGNATURE, 0)) {
		fail('INVALID_PNG_SIGNATURE', 'resource PNG must begin with the canonical PNG signature');
	}

	return Object.freeze({
		bytes,
		byteSize,
		contentType: RESOURCE_PNG_CONTENT_TYPE,
		fileKind: RESOURCE_IMAGE_FILE_KIND,
		filename,
		normalizedExtension: RESOURCE_PNG_NORMALIZED_EXTENSION,
		sha256: await sha256(bytes),
	});
};

const validateJpeg = async (
	candidate: ResourceFileCandidate,
	filename: string,
	normalizedExtension: (typeof RESOURCE_JPEG_NORMALIZED_EXTENSIONS)[number],
): Promise<ValidatedResourceFile> => {
	const byteSize = candidate.bytes.byteLength;
	const bytes = snapshotCandidateBytes(candidate, 'JPEG');
	const hasValidSignature =
		bytes[0] === 0xff &&
		bytes[1] === 0xd8 &&
		bytes[2] === 0xff &&
		bytes[bytes.length - 2] === 0xff &&
		bytes[bytes.length - 1] === 0xd9;

	if (!hasValidSignature) {
		fail(
			'INVALID_JPEG_SIGNATURE',
			'resource JPEG must contain the required SOI, marker prefix, and EOI bytes',
		);
	}

	return Object.freeze({
		bytes,
		byteSize,
		contentType: RESOURCE_JPEG_CONTENT_TYPE,
		fileKind: RESOURCE_IMAGE_FILE_KIND,
		filename,
		normalizedExtension,
		sha256: await sha256(bytes),
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

	if (normalizedExtension === RESOURCE_PNG_NORMALIZED_EXTENSION) {
		return validatePng(candidate, filename);
	}

	if (
		normalizedExtension === RESOURCE_JPEG_NORMALIZED_EXTENSIONS[0] ||
		normalizedExtension === RESOURCE_JPEG_NORMALIZED_EXTENSIONS[1]
	) {
		return validateJpeg(candidate, filename, normalizedExtension);
	}

	if (normalizedExtension === RESOURCE_MARKDOWN_NORMALIZED_EXTENSION) {
		return validateText(candidate, filename, 'markdown', normalizedExtension);
	}

	if (normalizedExtension === RESOURCE_TEX_NORMALIZED_EXTENSION) {
		return validateText(candidate, filename, 'tex', normalizedExtension);
	}

	if (normalizedExtension === RESOURCE_PLAIN_TEXT_NORMALIZED_EXTENSION) {
		return validateText(candidate, filename, 'text', normalizedExtension);
	}

	if (isResourceSourceNormalizedExtension(normalizedExtension)) {
		return validateText(candidate, filename, 'source', normalizedExtension);
	}

	return fail('UNSUPPORTED_FILE_TYPE', 'submitted file type is not currently supported');
};
