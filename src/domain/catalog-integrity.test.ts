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

describe('catalog integrity', () => {
	it('accepts the static demo catalog', () => {
		const catalog = makeCatalog();

		expect(collectCatalogIntegrityIssues(catalog, storageOptions)).toEqual([]);
		expect(() => validateCatalogIntegrity(catalog, storageOptions)).not.toThrow();
	});

	it('represents common courses and curriculum-specific cycles without duplicating courses', () => {
		const catalog = makeCatalog();
		const calculusCourseRecords = catalog.courses.filter(
			(course) => course.id === 'course-demo-calculus-1',
		);
		const commonCalculusRelations = catalog.curriculumCourses.filter(
			(relation) => relation.courseId === 'course-demo-calculus-1',
		);
		const mathLinearAlgebra = findCurriculumCourse(
			catalog,
			'curriculum-demo-math-2026',
			'course-demo-linear-algebra',
		);
		const computingLinearAlgebra = findCurriculumCourse(
			catalog,
			'curriculum-demo-computing-2026',
			'course-demo-linear-algebra',
		);

		expect(calculusCourseRecords).toHaveLength(1);
		expect(commonCalculusRelations).toHaveLength(2);
		expect(commonCalculusRelations.every((relation) => relation.recommendedCycle === 1)).toBe(true);
		expect(mathLinearAlgebra.recommendedCycle).toBe(1);
		expect(computingLinearAlgebra.recommendedCycle).toBe(2);
		expect(computingLinearAlgebra.requirementType).toBe('elective');
	});

	it('detects duplicated identifiers and slugs', () => {
		const catalog = makeCatalog();
		const unit = first(catalog.academicUnits);
		const duplicatedIdUnit: AcademicUnit = {
			...unit,
			slug: 'unidad-demo-duplicada',
		};
		const duplicatedSlugUnit: AcademicUnit = {
			...unit,
			id: 'academic-unit-demo-duplicate-slug',
		};

		const issues = collectCatalogIntegrityIssues(
			{
				...catalog,
				academicUnits: [...catalog.academicUnits, duplicatedIdUnit, duplicatedSlugUnit],
			},
			storageOptions,
		);

		expect(issues).toEqual(
			expect.arrayContaining([
				expect.stringContaining('Identificador global duplicado'),
				expect.stringContaining('Slug de unidad academica duplicado'),
			]),
		);
	});

	it('detects missing units, curricula, courses, prerequisites and resources', () => {
		const catalog = makeCatalog();
		const curriculum = first(catalog.curricula);
		const relation = first(catalog.curriculumCourses);
		const resource = first(catalog.resources);
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
			...resource,
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
		const curriculumCourses = catalog.curriculumCourses.map((relation) =>
			relation.id === 'curriculum-course-demo-math-calculus-1'
				? { ...relation, prerequisiteCourseIds: ['course-demo-calculus-2'] }
				: relation,
		);

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
		const resource = first(catalog.resources);
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
