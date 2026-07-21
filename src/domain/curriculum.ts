export const CURRICULUM_STATUSES = ['active', 'historical'] as const;

export type CurriculumStatus = (typeof CURRICULUM_STATUSES)[number];

export interface Curriculum {
	readonly academicUnitId: string;
	readonly code: string;
	readonly effectivePeriod: string;
	readonly id: string;
	readonly name: string;
	readonly status: CurriculumStatus;
}
