export const CURRICULUM_COURSE_REQUIREMENT_TYPES = [
	'required',
	'elective',
	'pending-verification',
] as const;

export type CurriculumCourseRequirementType = (typeof CURRICULUM_COURSE_REQUIREMENT_TYPES)[number];

export interface CurriculumCourse {
	readonly courseId: string;
	readonly curriculumId: string;
	readonly id: string;
	readonly prerequisiteCourseIds: ReadonlyArray<string>;
	readonly recommendedCycle: number;
	readonly requirementType: CurriculumCourseRequirementType;
}

export const CURRICULUM_COURSE_REQUIREMENT_TYPE_LABELS: Record<
	CurriculumCourseRequirementType,
	string
> = {
	elective: 'Electivo',
	'pending-verification': 'Por verificar',
	required: 'Obligatorio',
};
