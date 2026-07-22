import { describe, expect, it } from 'vitest';
import academicTermsJson from '../content/catalog/academic-terms.json';
import academicUnitsJson from '../content/catalog/academic-units.json';
import coursesJson from '../content/catalog/courses.json';
import curriculaJson from '../content/catalog/curricula.json';
import curriculumCoursesJson from '../content/catalog/curriculum-courses.json';
import resourcesJson from '../content/catalog/resources.json';
import type { AcademicTerm } from './academic-term';
import type { AcademicUnit } from './academic-unit';
import { filterCourses } from './catalog-filters';
import type { CourseCatalogItem, CourseOffering } from './catalog-view';
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
	hours: { ...curriculumCourse.hours },
	prerequisiteCourseIds: [...curriculumCourse.prerequisiteCourseIds],
	source: { ...curriculumCourse.source },
	syllabus: { ...curriculumCourse.syllabus },
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

const findCurriculumByProgram = (catalog: CatalogCollections, programId: string): Curriculum => {
	const curriculum = catalog.curricula.find((candidate) => candidate.academicUnitId === programId);
	if (curriculum === undefined) {
		throw new Error('Plan curricular no encontrado: ' + programId);
	}

	return curriculum;
};

const getParentUnit = (
	unit: AcademicUnit | undefined,
	unitsById: ReadonlyMap<string, AcademicUnit>,
): AcademicUnit | undefined => {
	if (unit?.parentUnitId === undefined) {
		return undefined;
	}

	return unitsById.get(unit.parentUnitId);
};

const makeOffering = (
	unitsById: ReadonlyMap<string, AcademicUnit>,
	curriculaById: ReadonlyMap<string, Curriculum>,
	relation: CurriculumCourse,
): CourseOffering => {
	const curriculum = curriculaById.get(relation.curriculumId);
	if (curriculum === undefined) {
		throw new Error('Plan inexistente en fixture');
	}

	const program = unitsById.get(curriculum.academicUnitId);
	if (program === undefined) {
		throw new Error('Programa inexistente en fixture');
	}

	const school = getParentUnit(program, unitsById);
	const faculty = getParentUnit(school, unitsById);

	return { curriculum, curriculumCourse: relation, faculty, program, school };
};

const makeCourseItems = (catalog: CatalogCollections): ReadonlyArray<CourseCatalogItem> => {
	const unitsById = new Map(catalog.academicUnits.map((unit) => [unit.id, unit]));
	const curriculaById = new Map(catalog.curricula.map((curriculum) => [curriculum.id, curriculum]));

	return catalog.courses.map((course) => ({
		course,
		offerings: catalog.curriculumCourses
			.filter((relation) => relation.courseId === course.id)
			.map((relation) => makeOffering(unitsById, curriculaById, relation)),
	}));
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

const relationSummary = (catalog: CatalogCollections, courseCode: string) => {
	const curriculaById = new Map(catalog.curricula.map((curriculum) => [curriculum.id, curriculum]));
	return catalog.curriculumCourses
		.filter((relation) => relation.courseId === 'course:' + courseCode.toLocaleLowerCase('es'))
		.map((relation) => ({
			cycle: relation.recommendedCycle,
			programId: curriculaById.get(relation.curriculumId)?.academicUnitId,
			requirementType: relation.requirementType,
		}))
		.sort((left, right) => (left.programId ?? '').localeCompare(right.programId ?? '', 'es'));
};

describe('catalog integrity', () => {
	it('accepts the imported Plan 2018 catalog', () => {
		const catalog = makeCatalog();

		expect(collectCatalogIntegrityIssues(catalog, storageOptions)).toEqual([]);
		expect(() => validateCatalogIntegrity(catalog, storageOptions)).not.toThrow();
	});

	it('imports the expected normalized counts and stable course identity fields', () => {
		const catalog = makeCatalog();
		const courseIds = new Set(catalog.courses.map((course) => course.id));
		const curriculumIds = new Set(catalog.curricula.map((curriculum) => curriculum.id));
		const courseCodeCounts = countBy(catalog.courses, (course) => course.code);

		expect(catalog.courses).toHaveLength(386);
		expect(catalog.curriculumCourses).toHaveLength(556);
		expect(catalog.curricula).toHaveLength(5);
		expect(catalog.academicUnits).toHaveLength(11);
		expect(
			catalog.courses.every((course) => course.id === 'course:' + course.code.toLowerCase()),
		).toBe(true);
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
		expectUnique(catalog.curriculumCourses.map((relation) => relation.id));
		expect(catalog.curriculumCourses.every((relation) => courseIds.has(relation.courseId))).toBe(
			true,
		);
		expect(
			catalog.curriculumCourses.every((relation) => curriculumIds.has(relation.curriculumId)),
		).toBe(true);
		expect(catalog.resources.every((resource) => courseIds.has(resource.courseId))).toBe(true);

		for (const [code, count] of courseCodeCounts) {
			expect(count, code).toBe(1);
		}
	});

	it('keeps curriculum-specific requirements, cycles, prerequisites, syllabus labels and source rows valid', () => {
		const catalog = makeCatalog();
		const courseIds = new Set(catalog.courses.map((course) => course.id));

		expect(
			catalog.curriculumCourses.every((relation) =>
				relation.prerequisiteCourseIds.every((courseId) => courseIds.has(courseId)),
			),
		).toBe(true);
		expect(
			catalog.curriculumCourses
				.filter((relation) => relation.requirementType === 'required')
				.every(
					(relation) =>
						Number.isInteger(relation.recommendedCycle) &&
						relation.recommendedCycle !== null &&
						relation.recommendedCycle >= 1 &&
						relation.recommendedCycle <= 10,
				),
		).toBe(true);
		expect(
			catalog.curriculumCourses
				.filter((relation) => relation.requirementType !== 'required')
				.every((relation) => relation.recommendedCycle === null),
		).toBe(true);
		expect(catalog.curriculumCourses.every((relation) => relation.syllabus.url === null)).toBe(
			true,
		);
		expect(catalog.curriculumCourses.every((relation) => relation.source.file.length > 0)).toBe(
			true,
		);
		expect(catalog.curriculumCourses.every((relation) => relation.source.row > 0)).toBe(true);
	});

	it('preserves BEF01, CC421 and CC431 curriculum placements', () => {
		const catalog = makeCatalog();

		expect(relationSummary(catalog, 'BEF01')).toEqual([
			{ cycle: 3, programId: 'academic-unit:program:n1', requirementType: 'required' },
			{ cycle: 5, programId: 'academic-unit:program:n2', requirementType: 'required' },
			{ cycle: 2, programId: 'academic-unit:program:n3', requirementType: 'required' },
			{ cycle: 2, programId: 'academic-unit:program:n5', requirementType: 'required' },
			{ cycle: 6, programId: 'academic-unit:program:n6', requirementType: 'required' },
		]);
		expect(relationSummary(catalog, 'CC421')).toEqual([
			{
				cycle: null,
				programId: 'academic-unit:program:n2',
				requirementType: 'complementary-elective',
			},
			{ cycle: 7, programId: 'academic-unit:program:n6', requirementType: 'required' },
		]);
		expect(relationSummary(catalog, 'CC431')).toEqual([
			{
				cycle: null,
				programId: 'academic-unit:program:n2',
				requirementType: 'complementary-elective',
			},
			{ cycle: 7, programId: 'academic-unit:program:n6', requirementType: 'required' },
		]);
	});

	it('ignores cycle filtering without program and applies it within the selected program', () => {
		const catalog = makeCatalog();
		const items = makeCourseItems(catalog);
		const cycleWithoutProgram = filterCourses(items, { recommendedCycle: 7 });
		const n6CycleSeven = filterCourses(items, {
			programId: 'academic-unit:program:n6',
			recommendedCycle: 7,
		});
		const n2ComplementaryElectives = filterCourses(items, {
			programId: 'academic-unit:program:n2',
			requirementType: 'complementary-elective',
		});
		const n6CycleSevenCodes = new Set(n6CycleSeven.map((item) => item.course.code));
		const n2ComplementaryCodes = new Set(n2ComplementaryElectives.map((item) => item.course.code));

		expect(cycleWithoutProgram).toHaveLength(items.length);
		expect(
			n6CycleSeven.every((item) =>
				item.offerings.some(
					(offering) =>
						offering.program.id === 'academic-unit:program:n6' &&
						offering.curriculumCourse.recommendedCycle === 7,
				),
			),
		).toBe(true);
		expect(n6CycleSevenCodes.has('CC421')).toBe(true);
		expect(n6CycleSevenCodes.has('CC431')).toBe(true);
		expect(n2ComplementaryCodes.has('CC421')).toBe(true);
		expect(n2ComplementaryCodes.has('CC431')).toBe(true);
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
			id: 'course:bae01duplicate',
			slug: 'bae01-codigo-duplicado',
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

	it('detects invalid course identity, credit status and administrative assignment', () => {
		const catalog = makeCatalog();
		const course = first(catalog.courses);
		const invalidCourse: Course = {
			...course,
			adminAcademicUnitId: 'academic-unit:school:n1',
			adminAssignmentBasis: 'pending-verification',
			code: 'bad-101',
			credits: null,
			dataStatus: undefined,
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
				expect.stringContaining('Identificador de curso no coincide con codigo'),
				expect.stringContaining('Slug de curso no inicia con codigo'),
				expect.stringContaining('Curso con creditos pendientes sin estado de verificacion'),
				expect.stringContaining('Curso pendiente con administrador asignado'),
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

	it('detects invalid requirement cycles, syllabus state and source URLs', () => {
		const catalog = makeCatalog();
		const requiredRelation = catalog.curriculumCourses.find(
			(relation) => relation.requirementType === 'required',
		);
		const electiveRelation = catalog.curriculumCourses.find(
			(relation) => relation.requirementType === 'specialty-elective',
		);
		if (requiredRelation === undefined || electiveRelation === undefined) {
			throw new Error('Fixtures de relaciones requeridas ausentes');
		}

		const issues = collectCatalogIntegrityIssues(
			{
				...catalog,
				curriculumCourses: [
					...catalog.curriculumCourses,
					{
						...requiredRelation,
						id: 'curriculum-course:broken-required-cycle',
						recommendedCycle: null,
					},
					{
						...electiveRelation,
						id: 'curriculum-course:broken-elective-cycle',
						recommendedCycle: 1,
					},
					{
						...requiredRelation,
						id: 'curriculum-course:broken-syllabus-state',
						syllabus: {
							...requiredRelation.syllabus,
							linkStatus: 'label-only',
							url: 'https://example.invalid/silabo.pdf',
						},
					},
					{
						...requiredRelation,
						id: 'curriculum-course:broken-source-url',
						source: {
							...requiredRelation.source,
							curriculumUrl: 'not-a-url',
						},
					},
				],
			},
			storageOptions,
		);

		expect(issues).toEqual(
			expect.arrayContaining([
				expect.stringContaining('Curso obligatorio sin ciclo recomendado'),
				expect.stringContaining('Curso electivo con ciclo recomendado fijo'),
				expect.stringContaining('Silabo con URL sin estado verificado'),
				expect.stringContaining('Relacion curriculum-curso con URL fuente invalida'),
			]),
		);
	});

	it('detects direct circular prerequisite references inside one curriculum', () => {
		const catalog = makeCatalog();
		const n6Curriculum = findCurriculumByProgram(catalog, 'academic-unit:program:n6');
		const cc112 = findCurriculumCourse(catalog, n6Curriculum.id, 'course:cc112');
		const cc211 = findCurriculumCourse(catalog, n6Curriculum.id, 'course:cc211');
		const curriculumCourses = catalog.curriculumCourses.map((relation) => {
			if (relation.id === cc112.id) {
				return { ...relation, prerequisiteCourseIds: ['course:cc211'] };
			}

			if (relation.id === cc211.id) {
				return { ...relation, prerequisiteCourseIds: ['course:cc112'] };
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
