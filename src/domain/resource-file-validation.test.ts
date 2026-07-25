import { describe, expect, it } from 'vitest';
import {
	RESOURCE_FILE_MAX_BYTES,
	ResourceFileValidationError,
	type ResourceFileCandidate,
	type ResourceFileValidationErrorCode,
	validateResourceFile,
} from './resource-file-validation';

const encoder = new TextEncoder();
const MINIMAL_PDF_TEXT = '%PDF-1.7\n1 0 obj\n<<>>\nendobj\n%%EOF\n';
const MINIMAL_PDF_SHA256 = '14fb1bb0a3f76503d164c7fd78a07c420c2f07eecd41793b406c6f75f2bc2aba';

const makeCandidate = (overrides: Partial<ResourceFileCandidate> = {}): ResourceFileCandidate => ({
	bytes: encoder.encode(MINIMAL_PDF_TEXT),
	declaredContentType: 'application/pdf',
	filename: 'exam.pdf',
	...overrides,
});

const makeSizedPdf = (size: number): Uint8Array => {
	const bytes = new Uint8Array(size);
	bytes.fill(0x20);
	bytes.set(encoder.encode('%PDF-'), 0);
	bytes.set(encoder.encode('%%EOF\n'), size - 6);

	return bytes;
};

const expectValidationError = async (
	candidate: ResourceFileCandidate,
	code: ResourceFileValidationErrorCode,
): Promise<void> => {
	await expect(validateResourceFile(candidate)).rejects.toMatchObject({
		code,
		name: 'ResourceFileValidationError',
	});
};

describe('ResourceFile validation dispatcher', () => {
	it.each(['', 'application/octet-stream', 'text/plain', 'application/pdf'])(
		'accepts a structurally valid PDF despite declared MIME %j',
		async (declaredContentType) => {
			const result = await validateResourceFile(
				makeCandidate({
					declaredContentType,
					filename: ' exam.PDF ',
				}),
			);

			expect(result).toMatchObject({
				contentType: 'application/pdf',
				fileKind: 'pdf',
				filename: 'exam.PDF',
				normalizedExtension: '.pdf',
			});
		},
	);

	it('copies exact bytes and hashes the stabilized stored snapshot', async () => {
		const sourceBytes = encoder.encode(MINIMAL_PDF_TEXT);
		const result = await validateResourceFile(makeCandidate({ bytes: sourceBytes }));

		expect(result.byteSize).toBe(sourceBytes.byteLength);
		expect(result.sha256).toBe(MINIMAL_PDF_SHA256);
		expect(result.bytes).not.toBe(sourceBytes);
		expect(result.bytes).toEqual(sourceBytes);

		sourceBytes.fill(0);

		expect(result.bytes[0]).toBe(0x25);
		expect(result.sha256).toBe(MINIMAL_PDF_SHA256);
	});

	it.each(['notes.png', 'photo.jpg', 'notes.md', 'solution.py'])(
		'rejects the not-yet-enabled extension in %j',
		async (filename) => {
			await expectValidationError(makeCandidate({ filename }), 'UNSUPPORTED_FILE_TYPE');
		},
	);

	it.each([
		['', 'MISSING_FILENAME'],
		['   ', 'MISSING_FILENAME'],
		['.pdf', 'INVALID_FILENAME'],
		['folder/exam.pdf', 'INVALID_FILENAME'],
		['folder\\exam.pdf', 'INVALID_FILENAME'],
		['exam\r\n.pdf', 'INVALID_FILENAME'],
		['exam\u007f.pdf', 'INVALID_FILENAME'],
	] as const)('rejects the unsafe filename %j', async (filename, expectedCode) => {
		await expectValidationError(makeCandidate({ filename }), expectedCode);
	});

	it.each(['exam', 'exam.', 'exam.txt'])(
		'rejects the unsupported filename %j without MIME classification',
		async (filename) => {
			await expectValidationError(
				makeCandidate({ filename, declaredContentType: 'application/pdf' }),
				'UNSUPPORTED_FILE_TYPE',
			);
		},
	);

	it('accepts a PDF at the exact decimal size limit', async () => {
		const result = await validateResourceFile(
			makeCandidate({ bytes: makeSizedPdf(RESOURCE_FILE_MAX_BYTES) }),
		);

		expect(result.byteSize).toBe(RESOURCE_FILE_MAX_BYTES);
		expect(result.sha256).toMatch(/^[0-9a-f]{64}$/);
	});

	it('rejects an empty PDF', async () => {
		await expectValidationError(makeCandidate({ bytes: new Uint8Array() }), 'EMPTY_FILE');
	});

	it('rejects a PDF larger than 10 MB decimal', async () => {
		await expectValidationError(
			makeCandidate({ bytes: new Uint8Array(RESOURCE_FILE_MAX_BYTES + 1) }),
			'FILE_TOO_LARGE',
		);
	});

	it('rejects content without the PDF header', async () => {
		await expectValidationError(
			makeCandidate({ bytes: encoder.encode('not a PDF\n%%EOF\n') }),
			'INVALID_PDF_HEADER',
		);
	});

	it('rejects a truncated PDF without an EOF marker', async () => {
		await expectValidationError(
			makeCandidate({ bytes: encoder.encode('%PDF-1.7\ntruncated') }),
			'INVALID_PDF_TRAILER',
		);
	});

	it('rejects non-whitespace data after the EOF marker', async () => {
		await expectValidationError(
			makeCandidate({ bytes: encoder.encode('%PDF-1.7\n%%EOF\nunexpected') }),
			'INVALID_PDF_TRAILER',
		);
	});

	it('rejects an EOF marker farther than 1024 bytes from the end', async () => {
		const prefix = encoder.encode('%PDF-1.7\n%%EOF');
		const bytes = new Uint8Array(prefix.length + 1_025);

		bytes.set(prefix);
		bytes.fill(0x20, prefix.length);

		await expectValidationError(makeCandidate({ bytes }), 'INVALID_PDF_TRAILER');
	});

	it('accepts PDF whitespace after the EOF marker', async () => {
		const result = await validateResourceFile(
			makeCandidate({ bytes: encoder.encode('%PDF-1.7\n%%EOF\u0000\t\n\f\r ') }),
		);

		expect(result.sha256).toMatch(/^[0-9a-f]{64}$/);
	});

	it('uses the generic ResourceFile validation error type', async () => {
		await expect(
			validateResourceFile(makeCandidate({ filename: 'future.png' })),
		).rejects.toBeInstanceOf(ResourceFileValidationError);
	});
});
