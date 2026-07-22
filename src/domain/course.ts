export const COURSE_STATUSES = ['active', 'historical'] as const;
export const COURSE_DATA_STATUSES = ['pending-verification'] as const;

export const COURSE_ADMIN_ASSIGNMENT_BASES = [
	'prefix-rule',
	'verified-manual',
	'pending-verification',
] as const;

export type CourseStatus = (typeof COURSE_STATUSES)[number];
export type CourseDataStatus = (typeof COURSE_DATA_STATUSES)[number];

export type CourseAdminAssignmentBasis = (typeof COURSE_ADMIN_ASSIGNMENT_BASES)[number];

export interface Course {
	readonly id: string;
	readonly code: string;
	readonly slug: string;
	readonly name: string;

	readonly credits: number | null;
	readonly summary: string | null;
	readonly tags: ReadonlyArray<string>;

	readonly adminAcademicUnitId: string | null;
	readonly adminAssignmentBasis: CourseAdminAssignmentBasis;

	readonly status: CourseStatus;
	readonly dataStatus?: CourseDataStatus;
}

export const formatCourseCredits = (credits: Course['credits']): string =>
	credits === null ? 'Por verificar' : String(credits);

export const formatCourseCreditsWithUnit = (credits: Course['credits']): string =>
	credits === null ? 'Créditos por verificar' : `${credits} créditos`;
