export const CURRICULUM_STATUSES = ['active', 'historical', 'pending-verification'] as const;

export type CurriculumStatus = (typeof CURRICULUM_STATUSES)[number];

export interface Curriculum {
	readonly academicUnitId: string;
	readonly code: string;
	readonly effectivePeriod: string;
	readonly id: string;
	readonly name: string;
	readonly sourceUrl: string;
	readonly status: CurriculumStatus;
}

export const CURRICULUM_STATUS_LABELS: Record<CurriculumStatus, string> = {
	active: 'Activo',
	historical: 'Histórico',
	'pending-verification': 'Pendiente de verificación',
};
