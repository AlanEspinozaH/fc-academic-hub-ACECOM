export {
	ACADEMIC_TERM_ID_PATTERN,
	isAcademicTermId,
	parseAcademicTermId,
	type AcademicTerm,
} from './academic-term';
export {
	ACADEMIC_UNIT_STATUSES,
	ACADEMIC_UNIT_TYPES,
	type AcademicUnit,
	type AcademicUnitStatus,
	type AcademicUnitType,
} from './academic-unit';
export {
	filterCourses,
	filterResources,
	isResourceType,
	parseRecommendedCycleFilter,
	parseSolutionAvailabilityFilter,
	type CourseFilters,
	type ResourceFilters,
	type SolutionAvailabilityFilter,
} from './catalog-filters';
export {
	CATALOG_STORAGE_CONFIGURED,
	CatalogIntegrityError,
	collectCatalogIntegrityIssues,
	validateCatalogIntegrity,
	type CatalogCollections,
	type CatalogIntegrityOptions,
} from './catalog-integrity';
export type { CourseCatalogItem, CourseOffering } from './catalog-view';
export { COURSE_STATUSES, type Course, type CourseStatus } from './course';
export {
	CURRICULUM_COURSE_REQUIREMENT_TYPE_LABELS,
	CURRICULUM_COURSE_REQUIREMENT_TYPES,
	type CurriculumCourse,
	type CurriculumCourseRequirementType,
} from './curriculum-course';
export { CURRICULUM_STATUSES, type Curriculum, type CurriculumStatus } from './curriculum';
export {
	RESOURCE_TYPE_LABELS,
	RESOURCE_TYPES,
	REVIEW_STATUSES,
	RIGHTS_STATUSES,
	RESOURCE_VISIBILITIES,
	type AcademicResource,
	type ResourceType,
	type ResourceVisibility,
	type ReviewStatus,
	type RightsStatus,
} from './resource';
export {
	RESOURCE_FILE_MAX_BYTES,
	RESOURCE_MARKDOWN_NORMALIZED_EXTENSION,
	RESOURCE_PDF_CONTENT_TYPE,
	RESOURCE_PDF_FILE_KIND,
	RESOURCE_PDF_NORMALIZED_EXTENSION,
	RESOURCE_PLAIN_TEXT_NORMALIZED_EXTENSION,
	RESOURCE_SOURCE_NORMALIZED_EXTENSIONS,
	RESOURCE_TEX_NORMALIZED_EXTENSION,
	RESOURCE_TEXT_CONTENT_TYPE,
	RESOURCE_TEXT_MAX_BYTES,
	ResourceFileValidationError,
	validateResourceFile,
	type ResourceFileCandidate,
	type ResourceFileKind,
	type ResourceFileValidationErrorCode,
	type ResourceSourceNormalizedExtension,
	type ValidatedResourceFile,
} from './resource-file-validation';
