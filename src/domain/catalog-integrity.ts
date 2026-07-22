import { isAcademicTermId, type AcademicTerm } from './academic-term';
import type { AcademicUnit } from './academic-unit';
import type { Course } from './course';
import type { CurriculumCourse } from './curriculum-course';
import type { Curriculum } from './curriculum';
import type { AcademicResource } from './resource';

export const CATALOG_STORAGE_CONFIGURED = false;

export interface CatalogCollections {
	readonly academicTerms: ReadonlyArray<AcademicTerm>;
	readonly academicUnits: ReadonlyArray<AcademicUnit>;
	readonly courses: ReadonlyArray<Course>;
	readonly curricula: ReadonlyArray<Curriculum>;
	readonly curriculumCourses: ReadonlyArray<CurriculumCourse>;
	readonly resources: ReadonlyArray<AcademicResource>;
}

export interface CatalogIntegrityOptions {
	readonly storageConfigured: boolean;
}

export class CatalogIntegrityError extends Error {
	readonly issues: ReadonlyArray<string>;

	constructor(issues: ReadonlyArray<string>) {
		super('Catalogo academico inconsistente:\n' + issues.map((issue) => '- ' + issue).join('\n'));
		this.name = 'CatalogIntegrityError';
		this.issues = issues;
	}
}

interface NamedValue {
	readonly label: string;
	readonly value: string;
}

const RESOURCE_FILE_REFERENCE_PATTERN =
	/\b(?:https?:\/\/|r2:\/\/|s3:\/\/|[A-Za-z0-9_./-]+\.(?:pdf|tex|zip|docx?|pptx?))\b/i;
const COURSE_ID_PATTERN = /^course:[a-z0-9]+$/;
const COURSE_CODE_PATTERN = /^[A-Z0-9]+$/;

const duplicateValues = (values: ReadonlyArray<NamedValue>): ReadonlyArray<string> => {
	const seen = new Set<string>();
	const duplicates = new Set<string>();

	for (const { value } of values) {
		if (seen.has(value)) {
			duplicates.add(value);
		}

		seen.add(value);
	}

	return [...duplicates].sort((left, right) => left.localeCompare(right, 'es'));
};

const addDuplicateIssues = (
	issues: Array<string>,
	label: string,
	values: ReadonlyArray<NamedValue>,
): void => {
	for (const duplicate of duplicateValues(values)) {
		issues.push(label + ' duplicado: ' + duplicate);
	}
};

const idValues = <T extends { readonly id: string }>(
	collection: string,
	items: ReadonlyArray<T>,
): ReadonlyArray<NamedValue> => items.map((item) => ({ label: collection, value: item.id }));

const slugValues = <T extends { readonly slug: string }>(
	collection: string,
	items: ReadonlyArray<T>,
): ReadonlyArray<NamedValue> => items.map((item) => ({ label: collection, value: item.slug }));

const toIdSet = <T extends { readonly id: string }>(items: ReadonlyArray<T>): ReadonlySet<string> =>
	new Set(items.map((item) => item.id));

const toIdMap = <T extends { readonly id: string }>(
	items: ReadonlyArray<T>,
): ReadonlyMap<string, T> => new Map(items.map((item) => [item.id, item]));

const textFromResource = (resource: AcademicResource): string =>
	[resource.title, resource.description, resource.evaluation ?? '', ...resource.tags].join(' ');

const validateAcademicTerms = (
	issues: Array<string>,
	academicTerms: ReadonlyArray<AcademicTerm>,
): void => {
	for (const term of academicTerms) {
		if (!isAcademicTermId(term.id)) {
			issues.push('Periodo academico invalido: ' + term.id);
			continue;
		}

		const [year, period] = term.id.split('-').map(Number);
		if (term.year !== year || term.period !== period) {
			issues.push('Periodo academico no coincide con su id: ' + term.id);
		}
	}
};

const validateAcademicUnits = (
	issues: Array<string>,
	academicUnits: ReadonlyArray<AcademicUnit>,
): void => {
	const unitsById = toIdMap(academicUnits);

	for (const unit of academicUnits) {
		if (unit.unitType === 'faculty' && unit.parentUnitId !== undefined) {
			issues.push('Facultad con unidad padre inesperada: ' + unit.id);
		}

		if (unit.unitType !== 'faculty' && unit.parentUnitId === undefined) {
			issues.push('Unidad academica sin padre: ' + unit.id);
			continue;
		}

		if (unit.parentUnitId === undefined) {
			continue;
		}

		const parent = unitsById.get(unit.parentUnitId);
		if (parent === undefined) {
			issues.push(
				'Unidad academica con padre inexistente: ' + unit.id + ' -> ' + unit.parentUnitId,
			);
			continue;
		}

		if (unit.unitType === 'school' && parent.unitType !== 'faculty') {
			issues.push('Escuela con padre que no es facultad: ' + unit.id + ' -> ' + parent.id);
		}

		if (unit.unitType === 'program' && parent.unitType !== 'school') {
			issues.push('Programa con padre que no es escuela: ' + unit.id + ' -> ' + parent.id);
		}
	}
};

const validateCourses = (issues: Array<string>, courses: ReadonlyArray<Course>): void => {
	for (const course of courses) {
		if (!COURSE_ID_PATTERN.test(course.id)) {
			issues.push('Identificador de curso invalido: ' + course.id);
		}

		if (!COURSE_CODE_PATTERN.test(course.code)) {
			issues.push('Codigo de curso invalido: ' + course.code);
		}

		const expectedSlugPrefix = course.code.toLocaleLowerCase('es') + '-';
		if (!course.slug.startsWith(expectedSlugPrefix)) {
			issues.push('Slug de curso no inicia con codigo: ' + course.id + ' -> ' + course.slug);
		}

		if (course.credits === null && course.dataStatus !== 'pending-verification') {
			issues.push('Curso con creditos pendientes sin estado de verificacion: ' + course.id);
		}
	}
};

const validateCurricula = (
	issues: Array<string>,
	catalog: CatalogCollections,
	academicUnitIds: ReadonlySet<string>,
): void => {
	const unitsById = toIdMap(catalog.academicUnits);

	for (const curriculum of catalog.curricula) {
		if (!academicUnitIds.has(curriculum.academicUnitId)) {
			issues.push(
				'Plan curricular con unidad academica inexistente: ' +
					curriculum.id +
					' -> ' +
					curriculum.academicUnitId,
			);
			continue;
		}

		if (unitsById.get(curriculum.academicUnitId)?.unitType !== 'program') {
			issues.push('Plan curricular asociado a unidad que no es programa: ' + curriculum.id);
		}
	}
};

const relationKey = (relation: CurriculumCourse): string =>
	relation.curriculumId + '::' + relation.courseId;

const validateCurriculumCourses = (
	issues: Array<string>,
	catalog: CatalogCollections,
	courseIds: ReadonlySet<string>,
	curriculumIds: ReadonlySet<string>,
): void => {
	const relationsByKey = new Map<string, CurriculumCourse>();
	const seenRelationshipKeys = new Set<string>();
	const duplicatedRelationshipKeys = new Set<string>();

	for (const relation of catalog.curriculumCourses) {
		const key = relationKey(relation);
		if (seenRelationshipKeys.has(key)) {
			duplicatedRelationshipKeys.add(key);
		}
		seenRelationshipKeys.add(key);
		relationsByKey.set(key, relation);
	}

	for (const duplicate of [...duplicatedRelationshipKeys].sort()) {
		issues.push('Relacion curriculum-curso duplicada: ' + duplicate);
	}

	const circularPairs = new Set<string>();

	for (const relation of catalog.curriculumCourses) {
		if (!curriculumIds.has(relation.curriculumId)) {
			issues.push(
				'Relacion curriculum-curso con plan inexistente: ' +
					relation.id +
					' -> ' +
					relation.curriculumId,
			);
		}

		if (!courseIds.has(relation.courseId)) {
			issues.push(
				'Relacion curriculum-curso con curso inexistente: ' +
					relation.id +
					' -> ' +
					relation.courseId,
			);
		}

		for (const prerequisiteCourseId of relation.prerequisiteCourseIds) {
			if (!courseIds.has(prerequisiteCourseId)) {
				issues.push(
					'Relacion curriculum-curso con prerrequisito inexistente: ' +
						relation.id +
						' -> ' +
						prerequisiteCourseId,
				);
				continue;
			}

			const prerequisiteKey = relation.curriculumId + '::' + prerequisiteCourseId;
			const prerequisiteRelation = relationsByKey.get(prerequisiteKey);
			if (prerequisiteRelation === undefined) {
				issues.push(
					'Prerrequisito fuera del mismo plan curricular: ' +
						relation.id +
						' -> ' +
						prerequisiteCourseId,
				);
				continue;
			}

			if (prerequisiteRelation.prerequisiteCourseIds.includes(relation.courseId)) {
				const pairKey = [relation.courseId, prerequisiteCourseId].sort().join(' <-> ');
				const curriculumPairKey = relation.curriculumId + ': ' + pairKey;
				if (!circularPairs.has(curriculumPairKey)) {
					issues.push('Referencia circular directa de prerrequisitos: ' + curriculumPairKey);
					circularPairs.add(curriculumPairKey);
				}
			}
		}
	}
};

const validateResourceRelationships = (
	issues: Array<string>,
	catalog: CatalogCollections,
	courseIds: ReadonlySet<string>,
	academicTermIds: ReadonlySet<string>,
	options: CatalogIntegrityOptions,
): void => {
	for (const resource of catalog.resources) {
		if (!courseIds.has(resource.courseId)) {
			issues.push('Recurso con curso inexistente: ' + resource.id + ' -> ' + resource.courseId);
		}

		if (resource.academicTermId !== undefined) {
			if (!isAcademicTermId(resource.academicTermId)) {
				issues.push(
					'Recurso con periodo academico invalido: ' +
						resource.id +
						' -> ' +
						resource.academicTermId,
				);
			} else if (!academicTermIds.has(resource.academicTermId)) {
				issues.push(
					'Recurso con periodo academico inexistente: ' +
						resource.id +
						' -> ' +
						resource.academicTermId,
				);
			}
		}

		if (resource.demo && RESOURCE_FILE_REFERENCE_PATTERN.test(textFromResource(resource))) {
			issues.push('Recurso demo contiene URL o referencia de archivo: ' + resource.id);
		}

		if (resource.fileAvailable && !options.storageConfigured) {
			issues.push('Recurso marcado fileAvailable sin storage configurado: ' + resource.id);
		}

		if (resource.resourceType === 'book-reference' && resource.fileAvailable) {
			issues.push('Referencia bibliografica marcada con archivo disponible: ' + resource.id);
		}
	}
};

export const collectCatalogIntegrityIssues = (
	catalog: CatalogCollections,
	options: CatalogIntegrityOptions = { storageConfigured: CATALOG_STORAGE_CONFIGURED },
): ReadonlyArray<string> => {
	const issues: Array<string> = [];
	const academicUnitIds = toIdSet(catalog.academicUnits);
	const curriculumIds = toIdSet(catalog.curricula);
	const courseIds = toIdSet(catalog.courses);
	const academicTermIds = toIdSet(catalog.academicTerms);

	addDuplicateIssues(issues, 'Identificador global', [
		...idValues('academicTerms', catalog.academicTerms),
		...idValues('academicUnits', catalog.academicUnits),
		...idValues('courses', catalog.courses),
		...idValues('curricula', catalog.curricula),
		...idValues('curriculumCourses', catalog.curriculumCourses),
		...idValues('resources', catalog.resources),
	]);
	addDuplicateIssues(
		issues,
		'Slug de unidad academica',
		slugValues('academicUnits', catalog.academicUnits),
	);
	addDuplicateIssues(issues, 'Slug de curso', slugValues('courses', catalog.courses));
	addDuplicateIssues(
		issues,
		'Codigo de curso',
		catalog.courses.map((course) => ({ label: 'courses', value: course.code })),
	);
	addDuplicateIssues(issues, 'Slug de recurso', slugValues('resources', catalog.resources));

	validateCourses(issues, catalog.courses);
	validateAcademicTerms(issues, catalog.academicTerms);
	validateAcademicUnits(issues, catalog.academicUnits);
	validateCurricula(issues, catalog, academicUnitIds);
	validateCurriculumCourses(issues, catalog, courseIds, curriculumIds);
	validateResourceRelationships(issues, catalog, courseIds, academicTermIds, options);

	return issues;
};

export const validateCatalogIntegrity = (
	catalog: CatalogCollections,
	options: CatalogIntegrityOptions = { storageConfigured: CATALOG_STORAGE_CONFIGURED },
): void => {
	const issues = collectCatalogIntegrityIssues(catalog, options);

	if (issues.length > 0) {
		throw new CatalogIntegrityError(issues);
	}
};
