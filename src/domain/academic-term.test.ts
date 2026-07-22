import { describe, expect, it } from 'vitest';
import { isAcademicTermId, parseAcademicTermId } from './academic-term';

describe('AcademicTerm', () => {
	it('validates terms like 2026-1 and 2026-2', () => {
		expect(isAcademicTermId('2026-1')).toBe(true);
		expect(isAcademicTermId('2026-2')).toBe(true);
		expect(parseAcademicTermId('2026-1')).toEqual({
			id: '2026-1',
			label: '2026-1',
			period: 1,
			year: 2026,
		});
	});

	it('rejects unsupported academic term shapes', () => {
		expect(isAcademicTermId('2026-I')).toBe(false);
		expect(isAcademicTermId('2026-3')).toBe(false);
		expect(() => parseAcademicTermId('2026-I')).toThrow('Periodo academico invalido');
	});
});
