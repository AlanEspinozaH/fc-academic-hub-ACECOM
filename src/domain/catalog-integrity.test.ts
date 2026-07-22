import { describe, expect, it } from 'vitest';
import academicTermsJson from '../content/catalog/academic-terms.json';
import academicUnitsJson from '../content/catalog/academic-units.json';
import coursesJson from '../content/catalog/courses.json';
import curriculaJson from '../content/catalog/curricula.json';
import curriculumCoursesJson from '../content/catalog/curriculum-courses.json';
import resourcesJson from '../content/catalog/resources.json';
import type { AcademicTerm } from './academic-term';
import type { AcademicUnit } from './academic-unit';
import {
	collectCatalogIntegrityIssues,
	validateCatalogIntegrity,
	type CatalogCollections,
} from './catalog-integrity';
import type { Course } from './course';
import type { CurriculumCourse } from './curriculum-course';
import type { Curriculum } from './curriculum';
import type { AcademicResource } from './resource';

const storageOptions = { storageConfigured: false } as const;
const requiredCourseCodes = [
	'BFI01',
	'BIC01',
	'BMA01',
	'BMA03',
	'BQU01',
	'BMA02',
	'BEF01',
	'BEG01',
	'BRC01',
	'BRN01',
	'CC112',
	'CC421',
	'CC431',
] as const;
const legacyCalculusCourseId = ['course-demo', 'calculus-1'].join('-');

const cloneAcademicTerm = (term: AcademicTerm): AcademicTerm => ({ ...term });
const cloneAcademicUnit = (unit: AcademicUnit): AcademicUnit => ({ ...unit });
const cloneCurriculum = (curriculum: Curriculum): Curriculum => ({ ...curriculum });
const cloneCurriculumCourse = (curriculumCourse: CurriculumCourse): CurriculumCourse => ({
	...curriculumCourse,
	prerequisiteCourseIds: [...curriculumCourse.prerequisiteCourseIds],
});
const cloneCourse = (course: Course): Course => ({
	...course,
	tags: [...course.tags],
});
const cloneResource = (resource: AcademicResource): AcademicResource => ({
	...resource,
	tags: [...resource.tags],
});

const first = <T>(items: ReadonlyArray<T>): T => {
	const item = items[0];
	if (item === undefined) {
		throw new Error('Fixture vacio inesperado');
	}

	return item;
};

const makeCatalog = (): CatalogCollections => ({
	academicTerms: (academicTermsJson as ReadonlyArray<AcademicTerm>).map(cloneAcademicTerm),
	academicUnits: (academicUnitsJson as ReadonlyArray<AcademicUnit>).map(cloneAcademicUnit),
	courses: (coursesJson as ReadonlyArray<Course>).map(cloneCourse),
	curricula: (curriculaJson as ReadonlyArray<Curriculum>).map(cloneCurriculum),
	curriculumCourses: (curriculumCoursesJson as ReadonlyArray<CurriculumCourse>).map(
		cloneCurriculumCourse,
	),
	resources: (resourcesJson as ReadonlyArray<AcademicResource>).map(cloneResource),
});

const makeResourceFixture = (courseId = 'course:bma01'): AcademicResource => ({
	academicTermId: '2026-1',
	courseId,
	demo: true,
	description: 'Registro demostrativo para pruebas de integridad sin archivo adjunto.',
	fileAvailable: false,
	hasSolution: false,
	id: 'resource-demo-integrity-fixture',
	language: 'es',
	resourceType: 'syllabus',
	reviewStatus: 'approved',
	rightsStatus: 'demo-only',
	slug: 'recurso-demo-integrity-fixture',
	tags: ['demostracion'],
	title: 'Recurso demostrativo de integridad',
	visibility: 'public',
});

const findCurriculumCourse = (
	catalog: CatalogCollections,
	curriculumId: string,
	courseId: string,
): CurriculumCourse => {
	const relation = catalog.curriculumCourses.find(
		(candidate) => candidate.curriculumId === curriculumId && candidate.courseId === courseId,
	);
	if (relation === undefined) {
		throw new Error('Relacion curriculum-curso no encontrada');
	}

	return relation;
};

const findCurriculumByCode = (catalog: CatalogCollections, code: string): Curriculum => {
	const curriculum = catalog.curricula.find((candidate) => candidate.code === code);
	if (curriculum === undefined) {
		throw new Error('Plan curricular no encontrado: ' + code);
	}

	return curriculum;
};

const countBy = <T>(items: ReadonlyArray<T>, value: (item: T) => string): Map<string, number> => {
	const counts = new Map<string, number>();
	for (const item of items) {
		const key = value(item);
		counts.set(key, (counts.get(key) ?? 0) + 1);
	}

	return counts;
};

const expectUnique = (values: ReadonlyArray<string>): void => {
	expect(new Set(values).size).toBe(values.length);
};

describe('catalog integrity', () => {
	it('accepts the static catalog', () => {
		const catalog = makeCatalog();

		expect(collectCatalogIntegrityIssues(catalog, storageOptions)).toEqual([]);
		expect(() => validateCatalogIntegrity(catalog, storageOptions)).not.toThrow();
	});

	it('enforces course identifiers, codes, slugs, references and required initial sample', () => {
		const catalog = makeCatalog();
		const courseIds = new Set(catalog.courses.map((course) => course.id));
		const courseCodeCounts = countBy(catalog.courses, (course) => course.code);
		const serializedCatalogData = JSON.stringify({
			courses: catalog.courses,
			curriculumCourses: catalog.curriculumCourses,
			resources: catalog.resources,
		});

		expect(catalog.courses).toHaveLength(requiredCourseCodes.length);
		expect(catalog.courses.every((course) => /^course:[a-z0-9]+$/.test(course.id))).toBe(true);
		expect(catalog.courses.every((course) => /^[A-Z0-9]+$/.test(course.code))).toBe(true);
		expect(
			catalog.courses.every((course) =>
				course.slug.startsWith(course.code.toLocaleLowerCase('es') + '-'),
			),
		).toBe(true);
		expectUnique(catalog.courses.map((course) => course.id));
		expectUnique(catalog.courses.map((course) => course.code));
		expectUnique(catalog.courses.map((course) => course.slug));
		expect(catalog.curriculumCourses.every((relation) => courseIds.has(relation.courseId))).toBe(
			true,
		);
		expect(
			catalog.curriculumCourses.every((relation) =>
				relation.prerequisiteCourseIds.every((courseId) => courseIds.has(courseId)),
			),
		).toBe(true);
		expect(catalog.resources.every((resource) => courseIds.has(resource.courseId))).toBe(true);

		for (const code of requiredCourseCodes) {
			expect(courseCodeCounts.get(code)).toBe(1);
		}
		expect(serializedCatalogData).not.toContain(legacyCalculusCourseId);
	});

	it('represents common BMA01 in more than one curriculum without duplicating Course', () => {
		const catalog = makeCatalog();
		const bma01CourseRecords = catalog.courses.filter((course) => course.id === 'course:bma01');
		const bma01Relations = catalog.curriculumCourses.filter(
			(relation) => relation.courseId === 'course:bma01',
		);
		const bma02ItemRelations = catalog.curriculumCourses.filter(
			(relation) => relation.courseId === 'course:bma02',
		);

		expect(bma01CourseRecords).toHaveLength(1);
		expect(new Set(bma01Relations.map((relation) => relation.curriculumId)).size).toBeGreaterThan(
			1,
		);
		expect(bma01Relations.every((relation) => relation.recommendedCycle === 1)).toBe(true);
		expect(bma02ItemRelations).toHaveLength(0);
	});

	it('places CC421 and CC431 in cycle 7 of plan N6 without inventing requirement type', () => {
		const catalog = makeCatalog();
		const n6Curriculum = findCurriculumByCode(catalog, 'N6');
		const artificialIntelligence = findCurriculumCourse(catalog, n6Curriculum.id, 'course:cc421');
		const computerGraphics = findCurriculumCourse(catalog, n6Curriculum.id, 'course:cc431');

		expect(artificialIntelligence.recommendedCycle).toBe(7);
		expect(computerGraphics.recommendedCycle).toBe(7);
		expect(artificialIntelligence.requirementType).toBe('pending-verification');
		expect(computerGraphics.requirementType).toBe('pending-verification');
	});

	it('detects duplicated identifiers, slugs and course codes', () => {
		const catalog = makeCatalog();
		const unit = first(catalog.academicUnits);
		const course = first(catalog.courses);
		const duplicatedIdUnit: AcademicUnit = {
			...unit,
			slug: 'unidad-demo-duplicada',
		};
		const duplicatedSlugUnit: AcademicUnit = {
			...unit,
			id: 'academic-unit-demo-duplicate-slug',
		};
		const duplicatedCodeCourse: Course = {
			...course,
			id: 'course:bfi01duplicate',
			slug: 'bfi01-codigo-duplicado',
		};

		const issues = collectCatalogIntegrityIssues(
			{
				...catalog,
				academicUnits: [...catalog.academicUnits, duplicatedIdUnit, duplicatedSlugUnit],
				courses: [...catalog.courses, duplicatedCodeCourse],
			},
			storageOptions,
		);

		expect(issues).toEqual(
			expect.arrayContaining([
				expect.stringContaining('Identificador global duplicado'),
				expect.stringContaining('Slug de unidad academica duplicado'),
				expect.stringContaining('Codigo de curso duplicado'),
			]),
		);
	});

	it('detects invalid course identity fields and pending credits without status', () => {
		const catalog = makeCatalog();
		const course =
			catalog.courses.find((candidate) => candidate.id === 'course:bma01') ??
			first(catalog.courses);
		const invalidCourse: Course = {
			...course,
			code: 'bad-101',
			credits: null,
			id: 'course-demo-invalid',
			slug: 'bad-101',
		};

		const issues = collectCatalogIntegrityIssues(
			{ ...catalog, courses: [...catalog.courses, invalidCourse] },
			storageOptions,
		);

		expect(issues).toEqual(
			expect.arrayContaining([
				expect.stringContaining('Identificador de curso invalido'),
				expect.stringContaining('Codigo de curso invalido'),
				expect.stringContaining('Slug de curso no inicia con codigo'),
				expect.stringContaining('Curso con creditos pendientes sin estado de verificacion'),
			]),
		);
	});

	it('detects missing units, curricula, courses, prerequisites and resources', () => {
		const catalog = makeCatalog();
		const curriculum = first(catalog.curricula);
		const relation = first(catalog.curriculumCourses);
		const brokenCurriculum: Curriculum = {
			...curriculum,
			academicUnitId: 'missing-program',
			code: 'BROKEN-DEMO',
			id: 'curriculum-demo-broken-unit',
		};
		const brokenRelation: CurriculumCourse = {
			...relation,
			courseId: 'missing-course',
			curriculumId: 'missing-curriculum',
			id: 'curriculum-course-demo-broken-relationships',
			prerequisiteCourseIds: ['missing-prerequisite'],
		};
		const brokenResource: AcademicResource = {
			...makeResourceFixture(),
			academicTermId: '2099-1',
			courseId: 'missing-course',
			id: 'resource-demo-broken-course',
			slug: 'recurso-demo-curso-roto',
		};

		const issues = collectCatalogIntegrityIssues(
			{
				...catalog,
				curricula: [...catalog.curricula, brokenCurriculum],
				curriculumCourses: [...catalog.curriculumCourses, brokenRelation],
				resources: [...catalog.resources, brokenResource],
			},
			storageOptions,
		);

		expect(issues).toEqual(
			expect.arrayContaining([
				expect.stringContaining('Plan curricular con unidad academica inexistente'),
				expect.stringContaining('Relacion curriculum-curso con plan inexistente'),
				expect.stringContaining('Relacion curriculum-curso con curso inexistente'),
				expect.stringContaining('Relacion curriculum-curso con prerrequisito inexistente'),
				expect.stringContaining('Recurso con curso inexistente'),
				expect.stringContaining('Recurso con periodo academico inexistente'),
			]),
		);
	});

	it('detects direct circular prerequisite references inside one curriculum', () => {
		const catalog = makeCatalog();
		const curriculumCourses = catalog.curriculumCourses.map((relation) => {
			if (relation.id === 'curriculum-course:n6:bma01') {
				return { ...relation, prerequisiteCourseIds: ['course:bma03'] };
			}

			if (relation.id === 'curriculum-course:n6:bma03') {
				return { ...relation, prerequisiteCourseIds: ['course:bma01'] };
			}

			return relation;
		});

		const issues = collectCatalogIntegrityIssues({ ...catalog, curriculumCourses }, storageOptions);

		expect(issues).toEqual(
			expect.arrayContaining([
				expect.stringContaining('Referencia circular directa de prerrequisitos'),
			]),
		);
	});

	it('detects invalid academic terms, file references and unavailable storage', () => {
		const catalog = makeCatalog();
		const term = first(catalog.academicTerms);
		const resource = makeResourceFixture();
		const invalidTerm: AcademicTerm = {
			...term,
			id: '2026-3',
		};
		const resourceWithUrl: AcademicResource = {
			...resource,
			description: 'Documento ficticio ubicado en https://example.invalid/demo.pdf',
			id: 'resource-demo-url-reference',
			slug: 'recurso-demo-url-reference',
		};
		const resourceWithFile: AcademicResource = {
			...resource,
			fileAvailable: true,
			id: 'resource-demo-file-without-storage',
			slug: 'recurso-demo-file-without-storage',
		};

		const issues = collectCatalogIntegrityIssues(
			{
				...catalog,
				academicTerms: [...catalog.academicTerms, invalidTerm],
				resources: [...catalog.resources, resourceWithUrl, resourceWithFile],
			},
			storageOptions,
		);

		expect(issues).toEqual(
			expect.arrayContaining([
				expect.stringContaining('Periodo academico invalido'),
				expect.stringContaining('Recurso demo contiene URL o referencia de archivo'),
				expect.stringContaining('Recurso marcado fileAvailable sin storage configurado'),
			]),
		);
	});
});
