export type ContentDispositionMode = 'inline' | 'attachment';

const DEFAULT_FILENAME = 'resource.pdf';
const RFC_8187_ATTR_CHAR = /^[A-Za-z0-9!#$&+.^_`|~-]$/;

const sanitizeFilename = (displayFilename: string): string => {
	let sanitized = '';

	for (const character of displayFilename.trim()) {
		const codePoint = character.codePointAt(0) ?? 0;

		if (codePoint <= 0x1f || codePoint === 0x7f || character === '/' || character === '\\') {
			sanitized += '_';
		} else {
			sanitized += character;
		}
	}

	return sanitized;
};

const toAsciiFallback = (filename: string): string => {
	let fallback = '';

	for (const character of filename) {
		const codePoint = character.codePointAt(0) ?? 0;

		if (
			codePoint >= 0x20 &&
			codePoint <= 0x7e &&
			character !== '"' &&
			character !== '\\' &&
			character !== '/'
		) {
			fallback += character;
		} else {
			fallback += '_';
		}
	}

	return /[A-Za-z0-9]/.test(fallback) ? fallback : DEFAULT_FILENAME;
};

const encodeUtf8Filename = (filename: string): string =>
	Array.from(new TextEncoder().encode(filename), (byte) => {
		const character = String.fromCharCode(byte);

		return RFC_8187_ATTR_CHAR.test(character)
			? character
			: `%${byte.toString(16).toUpperCase().padStart(2, '0')}`;
	}).join('');

export const buildContentDisposition = (
	mode: ContentDispositionMode,
	displayFilename: string,
): string => {
	const sanitizedFilename = sanitizeFilename(displayFilename);
	const safeFilename = /[^._\s-]/u.test(sanitizedFilename) ? sanitizedFilename : DEFAULT_FILENAME;
	const asciiFallback = toAsciiFallback(safeFilename);
	const encodedFilename = encodeUtf8Filename(safeFilename);

	return `${mode}; filename="${asciiFallback}"; filename*=UTF-8''${encodedFilename}`;
};
