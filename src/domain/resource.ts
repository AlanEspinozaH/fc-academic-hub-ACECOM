export const RESOURCE_TYPES = [
	'syllabus',
	'exam',
	'solution',
	'notes',
	'assignment',
	'laboratory',
	'class-material',
	'book-reference',
] as const;

export const REVIEW_STATUSES = ['draft', 'in-review', 'approved'] as const;
export const RESOURCE_VISIBILITIES = ['public', 'restricted'] as const;
export const RIGHTS_STATUSES = ['demo-only', 'bibliographic-reference-only'] as const;

export type ResourceType = (typeof RESOURCE_TYPES)[number];
export type ReviewStatus = (typeof REVIEW_STATUSES)[number];
export type ResourceVisibility = (typeof RESOURCE_VISIBILITIES)[number];
export type RightsStatus = (typeof RIGHTS_STATUSES)[number];

export interface AcademicResource {
	readonly academicTermId?: string;
	readonly courseId: string;
	readonly demo: boolean;
	readonly description: string;
	readonly evaluation?: string;
	readonly fileAvailable: boolean;
	readonly hasSolution: boolean;
	readonly id: string;
	readonly language: string;
	readonly resourceType: ResourceType;
	readonly reviewStatus: ReviewStatus;
	readonly rightsStatus: RightsStatus;
	readonly slug: string;
	readonly tags: ReadonlyArray<string>;
	readonly title: string;
	readonly visibility: ResourceVisibility;
}

export const RESOURCE_TYPE_LABELS: Record<ResourceType, string> = {
	assignment: 'Tarea',
	'book-reference': 'Referencia bibliografica',
	'class-material': 'Material de clase',
	exam: 'Evaluacion',
	laboratory: 'Laboratorio',
	notes: 'Apuntes',
	solution: 'Solucion',
	syllabus: 'Silabo',
};
