import type { AcademicTerm } from './academic-term';

export type CourseLevel = 'undergraduate' | 'graduate';

export interface Course {
	readonly code: string;
	readonly department: string;
	readonly id: string;
	readonly isDemo: boolean;
	readonly level: CourseLevel;
	readonly summary: string;
	readonly term: AcademicTerm;
	readonly title: string;
}
