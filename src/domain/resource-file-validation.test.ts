import { describe, expect, it } from 'vitest';
import {
	RESOURCE_FILE_MAX_BYTES,
	RESOURCE_SOURCE_NORMALIZED_EXTENSIONS,
	RESOURCE_TEXT_MAX_BYTES,
	ResourceFileValidationError,
	type ResourceFileCandidate,
	type ResourceFileValidationErrorCode,
	validateResourceFile,
} from './resource-file-validation';

const encoder = new TextEncoder();
const MINIMAL_PDF_TEXT = '%PDF-1.7\n1 0 obj\n<<>>\nendobj\n%%EOF\n';
const MINIMAL_PDF_SHA256 = '14fb1bb0a3f76503d164c7fd78a07c420c2f07eecd41793b406c6f75f2bc2aba';
const MINIMAL_PNG = new Uint8Array([
	0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x01, 0x02, 0x03, 0x04,
]);
const MINIMAL_PNG_SHA256 = '4353a1de7e0dcc4e87350e22d5c9ee9f3e70e8ce9c31533ec991bee8870c4814';
const MINIMAL_JPEG = new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0x01, 0x02, 0xff, 0xd9]);
const MINIMAL_JPEG_SHA256 = '6e18d2aca83ed8a4ca1d04fa88db9a2ea24d83665fbcf7de70ced8edbd7ac9fc';

const makeCandidate = (overrides: Partial<ResourceFileCandidate> = {}): ResourceFileCandidate => ({
	bytes: encoder.encode(MINIMAL_PDF_TEXT),
	declaredContentType: 'application/pdf',
	filename: 'exam.pdf',
	...overrides,
});

const makePngCandidate = (overrides: Partial<ResourceFileCandidate> = {}): ResourceFileCandidate =>
	makeCandidate({
		bytes: MINIMAL_PNG,
		declaredContentType: 'image/png',
		filename: 'photo.png',
		...overrides,
	});

const makeJpegCandidate = (overrides: Partial<ResourceFileCandidate> = {}): ResourceFileCandidate =>
	makeCandidate({
		bytes: MINIMAL_JPEG,
		declaredContentType: 'image/jpeg',
		filename: 'photo.jpg',
		...overrides,
	});

const makeSizedPdf = (size: number): Uint8Array => {
	const bytes = new Uint8Array(size);
	bytes.fill(0x20);
	bytes.set(encoder.encode('%PDF-'), 0);
	bytes.set(encoder.encode('%%EOF\n'), size - 6);

	return bytes;
};

const makeSizedPng = (size: number): Uint8Array => {
	const bytes = new Uint8Array(size);
	bytes.set(MINIMAL_PNG.subarray(0, 8), 0);

	return bytes;
};

const makeSizedJpeg = (size: number): Uint8Array => {
	const bytes = new Uint8Array(size);
	bytes.set([0xff, 0xd8, 0xff], 0);
	bytes.set([0xff, 0xd9], size - 2);

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
				makeCandidate({ declaredContentType, filename: ' exam.PDF ' }),
			);

			expect(result).toMatchObject({
				contentType: 'application/pdf',
				fileKind: 'pdf',
				filename: 'exam.PDF',
				normalizedExtension: '.pdf',
			});
		},
	);

	it.each(['', 'application/octet-stream', 'image/jpeg', 'image/png'])(
		'accepts PNG by extension/signature despite declared MIME %j',
		async (declaredContentType) => {
			const result = await validateResourceFile(
				makePngCandidate({ declaredContentType, filename: ' photo.PNG ' }),
			);

			expect(result).toMatchObject({
				contentType: 'image/png',
				fileKind: 'image',
				filename: 'photo.PNG',
				normalizedExtension: '.png',
			});
		},
	);

	it.each([
		['photo.jpg', '.jpg', ''],
		['photo.JPG', '.jpg', 'application/octet-stream'],
		['photo.jpeg', '.jpeg', 'image/png'],
		['photo.JPEG', '.jpeg', 'image/jpeg'],
	] as const)(
		'accepts JPEG %s by extension/signature despite declared MIME',
		async (filename, normalizedExtension, declaredContentType) => {
			const result = await validateResourceFile(
				makeJpegCandidate({ filename, declaredContentType }),
			);

			expect(result).toMatchObject({
				contentType: 'image/jpeg',
				fileKind: 'image',
				filename,
				normalizedExtension,
			});
		},
	);

	it.each([
		['PDF', makeCandidate(), MINIMAL_PDF_SHA256],
		['PNG', makePngCandidate(), MINIMAL_PNG_SHA256],
		['JPEG', makeJpegCandidate(), MINIMAL_JPEG_SHA256],
	] as const)(
		'copies exact %s bytes and hashes the stabilized stored snapshot',
		async (_, candidate, expectedSha256) => {
			const sourceBytes = Uint8Array.from(candidate.bytes);
			const result = await validateResourceFile({ ...candidate, bytes: sourceBytes });

			expect(result.byteSize).toBe(sourceBytes.byteLength);
			expect(result.sha256).toBe(expectedSha256);
			expect(result.bytes).not.toBe(sourceBytes);
			expect(result.bytes).toEqual(sourceBytes);

			sourceBytes.fill(0);

			expect(result.bytes[0]).not.toBe(0);
			expect(result.sha256).toBe(expectedSha256);
		},
	);

	it.each([
		['README.MD', 'markdown', '.md'],
		['formula.TeX', 'tex', '.tex'],
		['notes.TXT', 'text', '.txt'],
		...RESOURCE_SOURCE_NORMALIZED_EXTENSIONS.map(
			(extension) => [`solution${extension.toUpperCase()}`, 'source', extension] as const,
		),
	] as const)(
		'accepts canonical UTF-8 text metadata for %s',
		async (filename, fileKind, normalizedExtension) => {
			const bytes = encoder.encode('Árbol\r\nlínea\n');
			const result = await validateResourceFile(
				makeCandidate({
					bytes,
					declaredContentType: 'application/octet-stream',
					filename,
				}),
			);

			expect(result).toMatchObject({
				byteSize: bytes.byteLength,
				contentType: 'text/plain',
				fileKind,
				filename,
				normalizedExtension,
				sha256: 'dc7dd95695cd7d082e01d43c5631df855d543b89679d7f7804138aef15ce2caf',
			});
		},
	);

	it.each(['', 'application/octet-stream', 'text/html', 'application/javascript'])(
		'ignores client-declared MIME %j for an allowlisted textual file',
		async (declaredContentType) => {
			const result = await validateResourceFile(
				makeCandidate({
					bytes: encoder.encode('# safe markdown\n'),
					declaredContentType,
					filename: 'notes.md',
				}),
			);

			expect(result.contentType).toBe('text/plain');
			expect(result.fileKind).toBe('markdown');
		},
	);

	it.each([
		'icon.svg',
		'page.html',
		'page.htm',
		'page.xhtml',
		'data.xml',
		'data.json',
		'config.yaml',
		'config.yml',
		'style.css',
		'Program.cs',
		'Main.kt',
		'script.rb',
		'index.php',
		'app.swift',
		'notebook.ipynb',
		'bundle.zip',
		'program.exe',
		'library.jar',
		'module.wasm',
	])('rejects the forbidden or unspecified extension in %j', async (filename) => {
		await expectValidationError(
			makeCandidate({ bytes: encoder.encode('safe text'), filename }),
			'UNSUPPORTED_FILE_TYPE',
		);
	});

	it('preserves a UTF-8 BOM, CRLF, LF, exact bytes, and the exact-byte SHA', async () => {
		const sourceBytes = new Uint8Array([
			0xef, 0xbb, 0xbf, 0x6c, 0x69, 0x6e, 0x65, 0x20, 0x31, 0x0d, 0x0a, 0x6c, 0x69, 0x6e, 0x65,
			0x20, 0x32, 0x0a,
		]);
		const expectedBytes = Uint8Array.from(sourceBytes);
		const result = await validateResourceFile(
			makeCandidate({ bytes: sourceBytes, filename: 'notes.txt' }),
		);

		expect(result.bytes).not.toBe(sourceBytes);
		expect(result.bytes).toEqual(expectedBytes);
		expect(result.sha256).toBe('eccb0cfcd5680c420373910706abddc875676fd1bcca4fd8af156757a6e21c3b');

		sourceBytes.fill(0);
		expect(result.bytes).toEqual(expectedBytes);
	});

	it('accepts textual content at exactly 2,000,000 bytes', async () => {
		const result = await validateResourceFile(
			makeCandidate({
				bytes: new Uint8Array(RESOURCE_TEXT_MAX_BYTES).fill(0x61),
				filename: 'boundary.py',
			}),
		);

		expect(result.byteSize).toBe(RESOURCE_TEXT_MAX_BYTES);
		expect(result.sha256).toMatch(/^[0-9a-f]{64}$/);
	});

	it('rejects textual content above 2,000,000 bytes', async () => {
		await expectValidationError(
			makeCandidate({
				bytes: new Uint8Array(RESOURCE_TEXT_MAX_BYTES + 1).fill(0x61),
				filename: 'oversized.md',
			}),
			'FILE_TOO_LARGE',
		);
	});

	it('rejects empty textual files', async () => {
		await expectValidationError(
			makeCandidate({ bytes: new Uint8Array(), filename: 'empty.tex' }),
			'EMPTY_FILE',
		);
	});

	it('rejects invalid UTF-8 without attempting to rewrite it', async () => {
		await expectValidationError(
			makeCandidate({ bytes: new Uint8Array([0xc3, 0x28]), filename: 'invalid.txt' }),
			'INVALID_UTF8_TEXT',
		);
	});

	it('rejects a NUL byte in otherwise valid UTF-8 text', async () => {
		await expectValidationError(
			makeCandidate({ bytes: encoder.encode('before\u0000after'), filename: 'nul.java' }),
			'TEXT_CONTAINS_NUL',
		);
	});

	it.each([
		['', 'MISSING_FILENAME'],
		['   ', 'MISSING_FILENAME'],
		['.pdf', 'INVALID_FILENAME'],
		['.png', 'INVALID_FILENAME'],
		['.jpg', 'INVALID_FILENAME'],
		['.jpeg', 'INVALID_FILENAME'],
		...['.md', '.tex', '.txt', ...RESOURCE_SOURCE_NORMALIZED_EXTENSIONS].map(
			(filename) => [filename, 'INVALID_FILENAME'] as const,
		),
		['folder/exam.pdf', 'INVALID_FILENAME'],
		['folder/notes.md', 'INVALID_FILENAME'],
		['folder\\solution.py', 'INVALID_FILENAME'],
		['notes\r\n.md', 'INVALID_FILENAME'],
		['folder\\photo.png', 'INVALID_FILENAME'],
		['photo\r\n.png', 'INVALID_FILENAME'],
		['photo\u007f.jpeg', 'INVALID_FILENAME'],
	] as const)('rejects the unsafe filename %j', async (filename, expectedCode) => {
		await expectValidationError(makeCandidate({ filename }), expectedCode);
	});

	it.each(['exam', 'exam.', 'exam.bmp'])(
		'rejects the unsupported filename %j without MIME classification',
		async (filename) => {
			await expectValidationError(
				makeCandidate({ filename, declaredContentType: 'image/png' }),
				'UNSUPPORTED_FILE_TYPE',
			);
		},
	);

	it.each([
		['PDF', makeCandidate({ bytes: makeSizedPdf(RESOURCE_FILE_MAX_BYTES) })],
		['PNG', makePngCandidate({ bytes: makeSizedPng(RESOURCE_FILE_MAX_BYTES) })],
		['JPEG', makeJpegCandidate({ bytes: makeSizedJpeg(RESOURCE_FILE_MAX_BYTES) })],
	] as const)('accepts a %s at the exact decimal size limit', async (_, candidate) => {
		const result = await validateResourceFile(candidate);

		expect(result.byteSize).toBe(RESOURCE_FILE_MAX_BYTES);
		expect(result.sha256).toMatch(/^[0-9a-f]{64}$/);
	});

	it.each([
		['PDF', makeCandidate({ bytes: new Uint8Array() })],
		['PNG', makePngCandidate({ bytes: new Uint8Array() })],
		['JPEG', makeJpegCandidate({ bytes: new Uint8Array() })],
	] as const)('rejects an empty %s', async (_, candidate) => {
		await expectValidationError(candidate, 'EMPTY_FILE');
	});

	it.each([
		['PDF', makeCandidate({ bytes: new Uint8Array(RESOURCE_FILE_MAX_BYTES + 1) })],
		['PNG', makePngCandidate({ bytes: new Uint8Array(RESOURCE_FILE_MAX_BYTES + 1) })],
		['JPEG', makeJpegCandidate({ bytes: new Uint8Array(RESOURCE_FILE_MAX_BYTES + 1) })],
	] as const)('rejects a %s larger than 10 MB decimal', async (_, candidate) => {
		await expectValidationError(candidate, 'FILE_TOO_LARGE');
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

	it('rejects a .png filename containing JPEG bytes', async () => {
		await expectValidationError(makePngCandidate({ bytes: MINIMAL_JPEG }), 'INVALID_PNG_SIGNATURE');
	});

	it('requires the exact eight-byte PNG signature at offset zero', async () => {
		const invalidSignature = Uint8Array.from(MINIMAL_PNG);
		invalidSignature[7] = 0x00;

		await expectValidationError(
			makePngCandidate({ bytes: invalidSignature }),
			'INVALID_PNG_SIGNATURE',
		);
	});

	it.each(['photo.jpg', 'photo.jpeg'])('rejects %s containing PNG bytes', async (filename) => {
		await expectValidationError(
			makeJpegCandidate({ bytes: MINIMAL_PNG, filename }),
			'INVALID_JPEG_SIGNATURE',
		);
	});

	it.each([
		['missing SOI', new Uint8Array([0x00, 0xd8, 0xff, 0xe0, 0xff, 0xd9])],
		['missing marker prefix', new Uint8Array([0xff, 0xd8, 0x00, 0xe0, 0xff, 0xd9])],
		['missing EOI', new Uint8Array([0xff, 0xd8, 0xff, 0xe0, 0x00, 0x00])],
	] as const)('rejects JPEG bytes with %s', async (_, bytes) => {
		await expectValidationError(makeJpegCandidate({ bytes }), 'INVALID_JPEG_SIGNATURE');
	});

	it('uses the generic ResourceFile validation error type', async () => {
		await expect(
			validateResourceFile(makeCandidate({ filename: 'future.json' })),
		).rejects.toBeInstanceOf(ResourceFileValidationError);
	});
});
