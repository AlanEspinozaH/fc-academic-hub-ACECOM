import { RESOURCE_TYPES, type AcademicResource, type ResourceType } from './resource';
import type { CourseCatalogItem, CourseOffering } from './catalog-view';

export type SolutionAvailabilityFilter = 'with' | 'without';

export interface CourseFilters {
	readonly academicUnitId?: string;
	readonly programId?: string;
	readonly recommendedCycle?: number;
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

export const filterCourses = (
	items: ReadonlyArray<CourseCatalogItem>,
	filters: CourseFilters,
): ReadonlyArray<CourseCatalogItem> => {
	const text = normalizeSearch(filters.text);

	return items.filter((item) => {
		const matchesText = includesSearchText([item.course.code, item.course.name], text);
		const matchesProgram =
			filters.programId === undefined ||
			item.offerings.some((offering) => offering.program.id === filters.programId);
		const matchesAcademicUnit =
			filters.academicUnitId === undefined ||
			item.offerings.some((offering) =>
				offeringMatchesUnit(offering, filters.academicUnitId ?? ''),
			);
		const matchesCycle =
			filters.recommendedCycle === undefined ||
			item.offerings.some(
				(offering) => offering.curriculumCourse.recommendedCycle === filters.recommendedCycle,
			);

		return matchesText && matchesProgram && matchesAcademicUnit && matchesCycle;
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
