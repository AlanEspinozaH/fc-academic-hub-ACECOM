import { getCollection } from 'astro:content';
import resourceSource from '../content/catalog/resources.json';
import type { AcademicTerm } from './academic-term';
import type { AcademicUnit } from './academic-unit';
import {
	CATALOG_STORAGE_CONFIGURED,
	validateCatalogIntegrity,
	type CatalogCollections,
} from './catalog-integrity';
import {
	filterCourses,
	filterResources,
	type CourseFilters,
	type ResourceFilters,
} from './catalog-filters';
import type { CourseCatalogItem, CourseOffering } from './catalog-view';
import type { Course } from './course';
import type { CurriculumCourse } from './curriculum-course';
import type { Curriculum } from './curriculum';
import type { AcademicResource } from './resource';

interface ContentDataEntry<T> {
	readonly data: T;
}

export interface CatalogSnapshot extends CatalogCollections {
	readonly courseItems: ReadonlyArray<CourseCatalogItem>;
	readonly programs: ReadonlyArray<AcademicUnit>;
	readonly schools: ReadonlyArray<AcademicUnit>;
}

export type { CourseCatalogItem, CourseFilters, CourseOffering, ResourceFilters };

const dataFromEntries = <T>(entries: ReadonlyArray<ContentDataEntry<T>>): ReadonlyArray<T> =>
	entries.map((entry) => entry.data);

const sortByName = <T extends { readonly name: string }>(
	items: ReadonlyArray<T>,
): ReadonlyArray<T> => [...items].sort((left, right) => left.name.localeCompare(right.name, 'es'));

const sortCourses = (courses: ReadonlyArray<Course>): ReadonlyArray<Course> =>
	[...courses].sort((left, right) => left.code.localeCompare(right.code, 'es'));

const sortCourseItems = (
	items: ReadonlyArray<CourseCatalogItem>,
): ReadonlyArray<CourseCatalogItem> =>
	[...items].sort((left, right) => left.course.code.localeCompare(right.course.code, 'es'));

const sortResources = (
	resources: ReadonlyArray<AcademicResource>,
): ReadonlyArray<AcademicResource> =>
	[...resources].sort((left, right) => left.title.localeCompare(right.title, 'es'));

const sortAcademicTerms = (terms: ReadonlyArray<AcademicTerm>): ReadonlyArray<AcademicTerm> =>
	[...terms].sort((left, right) => left.id.localeCompare(right.id, 'es'));

const hasResourceSourceRecords = resourceSource.length > 0;

const getParentUnit = (
	unit: AcademicUnit | undefined,
	unitsById: ReadonlyMap<string, AcademicUnit>,
): AcademicUnit | undefined => {
	if (unit?.parentUnitId === undefined) {
		return undefined;
	}

	return unitsById.get(unit.parentUnitId);
};

const cycleSortValue = (relation: CurriculumCourse): number =>
	relation.recommendedCycle === null ? 99 : relation.recommendedCycle;

const requirementSortValue = (relation: CurriculumCourse): number => {
	if (relation.requirementType === 'required') {
		return 0;
	}

	return relation.requirementType === 'specialty-elective' ? 1 : 2;
};

const buildCourseOfferings = (catalog: CatalogCollections): ReadonlyArray<CourseOffering> => {
	const curriculaById = new Map(catalog.curricula.map((curriculum) => [curriculum.id, curriculum]));
	const unitsById = new Map(catalog.academicUnits.map((unit) => [unit.id, unit]));
	const offerings: Array<CourseOffering> = [];

	for (const curriculumCourse of catalog.curriculumCourses) {
		const curriculum = curriculaById.get(curriculumCourse.curriculumId);
		if (curriculum === undefined) {
			continue;
		}

		const program = unitsById.get(curriculum.academicUnitId);
		if (program === undefined) {
			continue;
		}

		const school = getParentUnit(program, unitsById);
		const faculty = getParentUnit(school, unitsById);
		offerings.push({ curriculum, curriculumCourse, faculty, program, school });
	}

	return offerings.sort((left, right) => {
		const cycleOrder =
			cycleSortValue(left.curriculumCourse) - cycleSortValue(right.curriculumCourse);
		if (cycleOrder !== 0) {
			return cycleOrder;
		}

		const requirementOrder =
			requirementSortValue(left.curriculumCourse) - requirementSortValue(right.curriculumCourse);
		if (requirementOrder !== 0) {
			return requirementOrder;
		}

		return left.curriculum.code.localeCompare(right.curriculum.code, 'es');
	});
};

const buildCourseItems = (catalog: CatalogCollections): ReadonlyArray<CourseCatalogItem> => {
	const offerings = buildCourseOfferings(catalog);
	return sortCourseItems(
		catalog.courses.map((course) => ({
			course,
			offerings: offerings.filter((offering) => offering.curriculumCourse.courseId === course.id),
		})),
	);
};

const buildCatalogSnapshot = async (): Promise<CatalogSnapshot> => {
	const [
		academicUnitEntries,
		curriculumEntries,
		curriculumCourseEntries,
		academicTermEntries,
		courseEntries,
		resourceEntries,
	] = await Promise.all([
		getCollection('academicUnits'),
		getCollection('curricula'),
		getCollection('curriculumCourses'),
		getCollection('academicTerms'),
		getCollection('courses'),
		hasResourceSourceRecords ? getCollection('resources') : Promise.resolve([]),
	]);

	const baseCatalog: CatalogCollections = {
		academicTerms: sortAcademicTerms(dataFromEntries<AcademicTerm>(academicTermEntries)),
		academicUnits: sortByName(dataFromEntries<AcademicUnit>(academicUnitEntries)),
		courses: sortCourses(dataFromEntries<Course>(courseEntries)),
		curricula: sortByName(dataFromEntries<Curriculum>(curriculumEntries)),
		curriculumCourses: dataFromEntries<CurriculumCourse>(curriculumCourseEntries),
		resources: sortResources(dataFromEntries<AcademicResource>(resourceEntries)),
	};

	validateCatalogIntegrity(baseCatalog, { storageConfigured: CATALOG_STORAGE_CONFIGURED });

	const schools = sortByName(
		baseCatalog.academicUnits.filter((unit) => unit.unitType === 'school'),
	);
	const programs = sortByName(
		baseCatalog.academicUnits.filter((unit) => unit.unitType === 'program'),
	);

	return {
		...baseCatalog,
		courseItems: buildCourseItems(baseCatalog),
		programs,
		schools,
	};
};

export const getCatalogSnapshot = async (): Promise<CatalogSnapshot> => buildCatalogSnapshot();

export const getAllAcademicUnits = async (): Promise<ReadonlyArray<AcademicUnit>> =>
	(await getCatalogSnapshot()).academicUnits;

export const getAllSchools = async (): Promise<ReadonlyArray<AcademicUnit>> =>
	(await getCatalogSnapshot()).schools;

export const getSchoolBySlug = async (slug: string): Promise<AcademicUnit | undefined> =>
	(await getCatalogSnapshot()).schools.find((school) => school.slug === slug);

export const getAllPrograms = async (): Promise<ReadonlyArray<AcademicUnit>> =>
	(await getCatalogSnapshot()).programs;

export const getAllCurricula = async (): Promise<ReadonlyArray<Curriculum>> =>
	(await getCatalogSnapshot()).curricula;

export const getAllAcademicTerms = async (): Promise<ReadonlyArray<AcademicTerm>> =>
	(await getCatalogSnapshot()).academicTerms;

export const getAllCourses = async (): Promise<ReadonlyArray<Course>> =>
	(await getCatalogSnapshot()).courses;

export const getAllCourseItems = async (): Promise<ReadonlyArray<CourseCatalogItem>> =>
	(await getCatalogSnapshot()).courseItems;

export const getCourseBySlug = async (slug: string): Promise<Course | undefined> =>
	(await getCatalogSnapshot()).courses.find((course) => course.slug === slug);

export const getCourseItemBySlug = async (slug: string): Promise<CourseCatalogItem | undefined> =>
	(await getCatalogSnapshot()).courseItems.find((item) => item.course.slug === slug);

export const getCourseItemsByAcademicUnit = async (
	academicUnitId: string,
): Promise<ReadonlyArray<CourseCatalogItem>> =>
	filterCourses((await getCatalogSnapshot()).courseItems, { academicUnitId });

export const getCoursesBySchool = async (
	schoolId: string,
): Promise<ReadonlyArray<CourseCatalogItem>> => getCourseItemsByAcademicUnit(schoolId);

export const getAllResources = async (): Promise<ReadonlyArray<AcademicResource>> =>
	(await getCatalogSnapshot()).resources;

export const getResourcesByCourse = async (
	courseId: string,
): Promise<ReadonlyArray<AcademicResource>> =>
	(await getCatalogSnapshot()).resources.filter((resource) => resource.courseId === courseId);

export const getFilteredCourses = async (
	filters: CourseFilters,
): Promise<ReadonlyArray<CourseCatalogItem>> =>
	filterCourses((await getCatalogSnapshot()).courseItems, filters);

export const getFilteredResources = async (
	filters: ResourceFilters,
): Promise<ReadonlyArray<AcademicResource>> =>
	filterResources((await getCatalogSnapshot()).resources, filters);
