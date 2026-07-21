export const ACADEMIC_UNIT_TYPES = ['faculty', 'school', 'program'] as const;
export const ACADEMIC_UNIT_STATUSES = ['active', 'inactive'] as const;

export type AcademicUnitType = (typeof ACADEMIC_UNIT_TYPES)[number];
export type AcademicUnitStatus = (typeof ACADEMIC_UNIT_STATUSES)[number];

export interface AcademicUnit {
	readonly abbreviation: string;
	readonly description: string;
	readonly id: string;
	readonly name: string;
	readonly parentUnitId?: string;
	readonly slug: string;
	readonly status: AcademicUnitStatus;
	readonly unitType: AcademicUnitType;
}
