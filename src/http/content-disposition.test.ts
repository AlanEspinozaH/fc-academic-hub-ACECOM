import { describe, expect, it } from 'vitest';
import { buildContentDisposition } from './content-disposition';

describe('safe Content-Disposition', () => {
	it('builds inline and attachment headers for a normal ASCII PDF filename', () => {
		expect(buildContentDisposition('inline', 'exam.pdf')).toBe(
			`inline; filename="exam.pdf"; filename*=UTF-8''exam.pdf`,
		);
		expect(buildContentDisposition('attachment', 'exam.pdf')).toBe(
			`attachment; filename="exam.pdf"; filename*=UTF-8''exam.pdf`,
		);
	});

	it('encodes spaces for filename* while retaining a safe quoted fallback', () => {
		expect(buildContentDisposition('attachment', 'final exam.pdf')).toBe(
			`attachment; filename="final exam.pdf"; filename*=UTF-8''final%20exam.pdf`,
		);
	});

	it('provides ASCII fallback and UTF-8 encoding for Unicode', () => {
		const header = buildContentDisposition('inline', 'Álgebra — práctica.pdf');

		expect(header).toContain('filename="_lgebra _ pr_ctica.pdf"');
		expect(header).toContain("filename*=UTF-8''%C3%81lgebra%20%E2%80%94%20pr%C3%A1ctica.pdf");
	});

	it('does not interpolate quotes into the quoted filename', () => {
		const header = buildContentDisposition('attachment', 'exam"final.pdf');

		expect(header).toContain('filename="exam_final.pdf"');
		expect(header).toContain('exam%22final.pdf');
		expect(header).not.toContain('filename="exam"final.pdf"');
	});

	it('neutralizes CR and LF so they cannot inject headers', () => {
		const header = buildContentDisposition('inline', 'exam.pdf\r\nX-Evil: yes');

		expect(header).not.toContain('\r');
		expect(header).not.toContain('\n');
		expect(header).toContain('exam.pdf__X-Evil: yes');
	});

	it('neutralizes path-like separators', () => {
		const header = buildContentDisposition('attachment', '../folder\\exam.pdf');

		expect(header).toContain('filename=".._folder_exam.pdf"');
		expect(header).not.toContain('../');
		expect(header).not.toContain('folder\\exam');
	});

	it.each(['', '   ', '\r\n', '...'])(
		'uses a safe fallback for an empty or degenerate name',
		(name) => {
			expect(buildContentDisposition('attachment', name)).toBe(
				`attachment; filename="resource.pdf"; filename*=UTF-8''resource.pdf`,
			);
		},
	);
});
