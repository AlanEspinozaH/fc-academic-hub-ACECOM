import { describe, expect, it } from 'vitest';
import {
	RESOURCE_PDF_MAX_BYTES,
	ResourcePdfValidationError,
	type ResourceFileCandidate,
	type ResourcePdfValidationErrorCode,
	validateResourcePdf,
} from './resource-file-validation';

const encoder = new TextEncoder();

const MINIMAL_PDF_TEXT = '%PDF-1.7\n1 0 obj\n<<>>\nendobj\n%%EOF\n';

const MINIMAL_PDF_SHA256 = '14fb1bb0a3f76503d164c7fd78a07c420c2f07eecd41793b406c6f75f2bc2aba';

const makeCandidate = (overrides: Partial<ResourceFileCandidate> = {}): ResourceFileCandidate => ({
	bytes: encoder.encode(MINIMAL_PDF_TEXT),
	contentType: 'application/pdf',
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
	code: ResourcePdfValidationErrorCode,
): Promise<void> => {
	await expect(validateResourcePdf(candidate)).rejects.toMatchObject({
		code,
		name: 'ResourcePdfValidationError',
	});
};

describe('resource PDF validation', () => {
	it('normalizes metadata, copies the bytes and calculates SHA-256', async () => {
		const sourceBytes = encoder.encode(MINIMAL_PDF_TEXT);

		const result = await validateResourcePdf(
			makeCandidate({
				bytes: sourceBytes,
				contentType: ' Application/PDF ',
				filename: ' exam.PDF ',
			}),
		);

		expect(result).toMatchObject({
			byteSize: sourceBytes.byteLength,
			contentType: 'application/pdf',
			filename: 'exam.PDF',
			sha256: MINIMAL_PDF_SHA256,
		});
		expect(result.bytes).not.toBe(sourceBytes);
		expect(result.bytes).toEqual(sourceBytes);

		sourceBytes.fill(0);

		expect(result.bytes[0]).toBe(0x25);
	});

	it('accepts a PDF at the exact size limit', async () => {
		const result = await validateResourcePdf(
			makeCandidate({
				bytes: makeSizedPdf(RESOURCE_PDF_MAX_BYTES),
			}),
		);

		expect(result.byteSize).toBe(RESOURCE_PDF_MAX_BYTES);
		expect(result.sha256).toMatch(/^[0-9a-f]{64}$/);
	});

	it.each([
		['', 'MISSING_FILENAME'],
		['   ', 'MISSING_FILENAME'],
		['.pdf', 'WRONG_FILE_EXTENSION'],
		['exam.txt', 'WRONG_FILE_EXTENSION'],
		['folder/exam.pdf', 'INVALID_FILENAME'],
		['folder\\exam.pdf', 'INVALID_FILENAME'],
		['exam\r\n.pdf', 'INVALID_FILENAME'],
	] as const)('rejects the invalid filename %j', async (filename, expectedCode) => {
		await expectValidationError(makeCandidate({ filename }), expectedCode);
	});

	it.each(['', 'text/plain', 'application/octet-stream', 'application/pdf; charset=binary'])(
		'rejects the invalid content type %j',
		async (contentType) => {
			await expectValidationError(makeCandidate({ contentType }), 'INVALID_CONTENT_TYPE');
		},
	);

	it('rejects an empty file', async () => {
		await expectValidationError(makeCandidate({ bytes: new Uint8Array() }), 'EMPTY_FILE');
	});

	it('rejects a file larger than 10 MB decimal', async () => {
		await expectValidationError(
			makeCandidate({
				bytes: new Uint8Array(RESOURCE_PDF_MAX_BYTES + 1),
			}),
			'FILE_TOO_LARGE',
		);
	});

	it('rejects content without the PDF header', async () => {
		await expectValidationError(
			makeCandidate({
				bytes: encoder.encode('not a PDF\n%%EOF\n'),
			}),
			'INVALID_PDF_HEADER',
		);
	});

	it('rejects a truncated PDF without an EOF marker', async () => {
		await expectValidationError(
			makeCandidate({
				bytes: encoder.encode('%PDF-1.7\ntruncated'),
			}),
			'INVALID_PDF_TRAILER',
		);
	});

	it('rejects non-whitespace data after the EOF marker', async () => {
		await expectValidationError(
			makeCandidate({
				bytes: encoder.encode('%PDF-1.7\n%%EOF\nunexpected'),
			}),
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
		const result = await validateResourcePdf(
			makeCandidate({
				bytes: encoder.encode('%PDF-1.7\n%%EOF\u0000\t\n\f\r '),
			}),
		);

		expect(result.sha256).toMatch(/^[0-9a-f]{64}$/);
	});

	it('uses a dedicated validation error type', async () => {
		await expect(
			validateResourcePdf(makeCandidate({ bytes: new Uint8Array() })),
		).rejects.toBeInstanceOf(ResourcePdfValidationError);
	});
});
