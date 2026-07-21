export const ACADEMIC_TERM_ID_PATTERN = /^\d{4}-[12]$/;

export interface AcademicTerm {
	readonly id: string;
	readonly label: string;
	readonly period: 1 | 2;
	readonly year: number;
}

export const isAcademicTermId = (value: string): boolean => ACADEMIC_TERM_ID_PATTERN.test(value);

export const parseAcademicTermId = (value: string): AcademicTerm => {
	if (!isAcademicTermId(value)) {
		throw new Error('Periodo academico invalido: ' + value);
	}

	const [year, period] = value.split('-').map(Number);

	if ((period !== 1 && period !== 2) || !Number.isInteger(year)) {
		throw new Error('Periodo academico invalido: ' + value);
	}

	return {
		id: value,
		label: value,
		period,
		year,
	};
};
