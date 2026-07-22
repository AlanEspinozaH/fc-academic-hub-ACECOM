import type { CourseCatalogItem, CourseOffering } from './catalog-view';
import {
	CURRICULUM_COURSE_REQUIREMENT_TYPES,
	type CurriculumCourseRequirementType,
} from './curriculum-course';
import { RESOURCE_TYPES, type AcademicResource, type ResourceType } from './resource';

export type SolutionAvailabilityFilter = 'with' | 'without';

export interface CourseFilters {
	readonly academicUnitId?: string;
	readonly programId?: string;
	readonly recommendedCycle?: number;
	readonly requirementType?: CurriculumCourseRequirementType;
	readonly text?: string;
}

export interface ResourceFilters {
	readonly academicTermId?: string;
	readonly courseId?: string;
	readonly resourceType?: ResourceType;
	readonly solutionAvailability?: SolutionAvailabilityFilter;
	readonly text?: string;
}

const normalizeSearch = (value: string | undefined): string =>
	value?.trim().toLocaleLowerCase('es') ?? '';

const includesSearchText = (haystack: ReadonlyArray<string>, text: string): boolean => {
	if (text.length === 0) {
		return true;
	}

	return haystack.join(' ').toLocaleLowerCase('es').includes(text);
};

const offeringMatchesUnit = (offering: CourseOffering, academicUnitId: string): boolean =>
	offering.program.id === academicUnitId ||
	offering.school?.id === academicUnitId ||
	offering.faculty?.id === academicUnitId;

export const parseRecommendedCycleFilter = (value: string | null): number | undefined => {
	if (value === null || value.trim() === '') {
		return undefined;
	}

	const parsed = Number.parseInt(value, 10);
	return Number.isInteger(parsed) && parsed > 0 ? parsed : undefined;
};

export const isCurriculumCourseRequirementType = (
	value: string,
): value is CurriculumCourseRequirementType =>
	CURRICULUM_COURSE_REQUIREMENT_TYPES.includes(value as CurriculumCourseRequirementType);

export const parseRequirementTypeFilter = (
	value: string | null,
): CurriculumCourseRequirementType | undefined => {
	if (value === null || value.trim() === '') {
		return undefined;
	}

	return isCurriculumCourseRequirementType(value) ? value : undefined;
};

export const isResourceType = (value: string): value is ResourceType =>
	RESOURCE_TYPES.includes(value as ResourceType);

export const parseSolutionAvailabilityFilter = (
	value: string | null,
): SolutionAvailabilityFilter | undefined => {
	if (value === 'with' || value === 'without') {
		return value;
	}

	return undefined;
};

const offeringMatchesCourseFilters = (
	offering: CourseOffering,
	filters: CourseFilters,
	effectiveCycle: number | undefined,
): boolean => {
	const matchesProgram =
		filters.programId === undefined || offering.program.id === filters.programId;
	const matchesAcademicUnit =
		filters.academicUnitId === undefined || offeringMatchesUnit(offering, filters.academicUnitId);
	const matchesCycle =
		effectiveCycle === undefined || offering.curriculumCourse.recommendedCycle === effectiveCycle;
	const matchesRequirement =
		filters.requirementType === undefined ||
		offering.curriculumCourse.requirementType === filters.requirementType;

	return matchesProgram && matchesAcademicUnit && matchesCycle && matchesRequirement;
};

export const filterCourses = (
	items: ReadonlyArray<CourseCatalogItem>,
	filters: CourseFilters,
): ReadonlyArray<CourseCatalogItem> => {
	const text = normalizeSearch(filters.text);
	const effectiveCycle = filters.programId === undefined ? undefined : filters.recommendedCycle;
	const hasOfferingFilters =
		filters.programId !== undefined ||
		filters.academicUnitId !== undefined ||
		effectiveCycle !== undefined ||
		filters.requirementType !== undefined;

	return items.filter((item) => {
		const matchesText = includesSearchText([item.course.code, item.course.name], text);
		const matchesOfferings =
			!hasOfferingFilters ||
			item.offerings.some((offering) =>
				offeringMatchesCourseFilters(offering, filters, effectiveCycle),
			);

		return matchesText && matchesOfferings;
	});
};

export const filterResources = (
	resources: ReadonlyArray<AcademicResource>,
	filters: ResourceFilters,
): ReadonlyArray<AcademicResource> => {
	const text = normalizeSearch(filters.text);

	return resources.filter((resource) => {
		const matchesText = includesSearchText(
			[resource.title, resource.description, resource.evaluation ?? '', ...resource.tags],
			text,
		);
		const matchesType =
			filters.resourceType === undefined || resource.resourceType === filters.resourceType;
		const matchesTerm =
			filters.academicTermId === undefined || resource.academicTermId === filters.academicTermId;
		const matchesCourse = filters.courseId === undefined || resource.courseId === filters.courseId;
		const matchesSolution =
			filters.solutionAvailability === undefined ||
			(filters.solutionAvailability === 'with' ? resource.hasSolution : !resource.hasSolution);

		return matchesText && matchesType && matchesTerm && matchesCourse && matchesSolution;
	});
};
