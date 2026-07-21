export const COURSE_STATUSES = ['active', 'historical'] as const;

export type CourseStatus = (typeof COURSE_STATUSES)[number];

export interface Course {
	readonly code: string;
	readonly credits: number;
	readonly id: string;
	readonly name: string;
	readonly slug: string;
	readonly status: CourseStatus;
	readonly summary: string;
	readonly tags: ReadonlyArray<string>;
}
