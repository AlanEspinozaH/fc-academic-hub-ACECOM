export const CURRICULUM_COURSE_REQUIREMENT_TYPES = [
	'required',
	'specialty-elective',
	'complementary-elective',
] as const;

export const CURRICULUM_COURSE_SYLLABUS_LINK_STATUSES = [
	'label-only',
	'not-listed',
	'verified-link',
] as const;

export type CurriculumCourseRequirementType = (typeof CURRICULUM_COURSE_REQUIREMENT_TYPES)[number];
export type CurriculumCourseSyllabusLinkStatus =
	(typeof CURRICULUM_COURSE_SYLLABUS_LINK_STATUSES)[number];

export interface CurriculumCourseSyllabus {
	readonly label: string | null;
	readonly url: string | null;
	readonly linkStatus: CurriculumCourseSyllabusLinkStatus;
}

export interface CurriculumCourseHours {
	readonly theoryRaw: string | null;
	readonly practiceRaw: string | null;
	readonly laboratoryRaw: string | null;
	readonly seminarRaw: string | null;
	readonly totalRaw: string | null;
}

export interface CurriculumCourseSource {
	readonly file: string;
	readonly row: number;
	readonly curriculumUrl: string;
}

export interface CurriculumCourse {
	readonly courseId: string;
	readonly curriculumId: string;
	readonly evaluationSystemCode: string | null;
	readonly hours: CurriculumCourseHours;
	readonly id: string;
	readonly prerequisiteCourseIds: ReadonlyArray<string>;
	readonly recommendedCycle: number | null;
	readonly requirementType: CurriculumCourseRequirementType;
	readonly source: CurriculumCourseSource;
	readonly syllabus: CurriculumCourseSyllabus;
	readonly typeCode: string | null;
}

export const CURRICULUM_COURSE_REQUIREMENT_TYPE_LABELS: Record<
	CurriculumCourseRequirementType,
	string
> = {
	'complementary-elective': 'Electivo complementario',
	required: 'Obligatorio',
	'specialty-elective': 'Electivo de especialidad',
};

export const formatRecommendedCycle = (cycle: CurriculumCourse['recommendedCycle']): string =>
	cycle === null ? 'Sin ciclo fijo' : 'Ciclo ' + cycle;
