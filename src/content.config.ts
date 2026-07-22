import { defineCollection } from 'astro:content';
import { file } from 'astro/loaders';
import { z } from 'astro/zod';
import { ACADEMIC_TERM_ID_PATTERN } from './domain/academic-term';
import { ACADEMIC_UNIT_STATUSES, ACADEMIC_UNIT_TYPES } from './domain/academic-unit';
import {
	COURSE_ADMIN_ASSIGNMENT_BASES,
	COURSE_DATA_STATUSES,
	COURSE_STATUSES,
} from './domain/course';
import {
	CURRICULUM_COURSE_REQUIREMENT_TYPES,
	CURRICULUM_COURSE_SYLLABUS_LINK_STATUSES,
} from './domain/curriculum-course';
import { CURRICULUM_STATUSES } from './domain/curriculum';
import {
	RESOURCE_TYPES,
	RESOURCE_VISIBILITIES,
	REVIEW_STATUSES,
	RIGHTS_STATUSES,
} from './domain/resource';

const slugSchema = z
	.string()
	.min(1)
	.regex(/^[a-z0-9]+(?:-[a-z0-9]+)*$/);

const tagSchema = z.array(z.string().min(1)).default([]);
const nullableRawTextSchema = z.string().min(1).nullable();
const urlSchema = z
	.string()
	.min(1)
	.refine((value) => URL.canParse(value), 'URL inválida');

const academicUnits = defineCollection({
	loader: file('src/content/catalog/academic-units.json'),
	schema: z
		.object({
			abbreviation: z.string().min(2),
			description: z.string().min(1).nullable(),
			id: z.string().min(1),
			name: z.string().min(1),
			parentUnitId: z.string().min(1).optional(),
			slug: slugSchema,
			status: z.enum(ACADEMIC_UNIT_STATUSES),
			unitType: z.enum(ACADEMIC_UNIT_TYPES),
		})
		.strict(),
});

const curricula = defineCollection({
	loader: file('src/content/catalog/curricula.json'),
	schema: z
		.object({
			academicUnitId: z.string().min(1),
			code: z.string().min(1),
			effectivePeriod: z.string().min(1),
			id: z.string().min(1),
			name: z.string().min(1),
			sourceUrl: urlSchema,
			status: z.enum(CURRICULUM_STATUSES),
		})
		.strict(),
});

const curriculumCourses = defineCollection({
	loader: file('src/content/catalog/curriculum-courses.json'),
	schema: z
		.object({
			courseId: z.string().min(1),
			curriculumId: z.string().min(1),
			evaluationSystemCode: z.string().min(1).nullable(),
			hours: z
				.object({
					laboratoryRaw: nullableRawTextSchema,
					practiceRaw: nullableRawTextSchema,
					seminarRaw: nullableRawTextSchema,
					theoryRaw: nullableRawTextSchema,
					totalRaw: nullableRawTextSchema,
				})
				.strict(),
			id: z.string().min(1),
			prerequisiteCourseIds: z.array(z.string().min(1)).default([]),
			recommendedCycle: z.number().int().min(1).max(10).nullable(),
			requirementType: z.enum(CURRICULUM_COURSE_REQUIREMENT_TYPES),
			source: z
				.object({
					curriculumUrl: urlSchema,
					file: z.string().min(1),
					row: z.number().int().positive(),
				})
				.strict(),
			syllabus: z
				.object({
					label: z.string().min(1).nullable(),
					linkStatus: z.enum(CURRICULUM_COURSE_SYLLABUS_LINK_STATUSES),
					url: urlSchema.nullable(),
				})
				.strict(),
			typeCode: z.string().min(1).nullable(),
		})
		.strict(),
});

const academicTerms = defineCollection({
	loader: file('src/content/catalog/academic-terms.json'),
	schema: z
		.object({
			id: z.string().regex(ACADEMIC_TERM_ID_PATTERN),
			label: z.string().min(1),
			period: z.union([z.literal(1), z.literal(2)]),
			year: z.number().int().min(2000).max(2100),
		})
		.strict(),
});

const courses = defineCollection({
	loader: file('src/content/catalog/courses.json'),
	schema: z
		.object({
			adminAcademicUnitId: z.string().min(1).nullable(),
			adminAssignmentBasis: z.enum(COURSE_ADMIN_ASSIGNMENT_BASES),
			code: z.string().min(1),
			credits: z.number().int().positive().nullable(),
			dataStatus: z.enum(COURSE_DATA_STATUSES).optional(),
			id: z.string().min(1),
			name: z.string().min(1),
			slug: slugSchema,
			status: z.enum(COURSE_STATUSES),
			summary: z.string().min(1).nullable(),
			tags: tagSchema,
		})
		.strict(),
});

const resources = defineCollection({
	loader: file('src/content/catalog/resources.json'),
	schema: z
		.object({
			academicTermId: z.string().regex(ACADEMIC_TERM_ID_PATTERN).optional(),
			courseId: z.string().min(1),
			demo: z.literal(true),
			description: z.string().min(1),
			evaluation: z.string().min(1).optional(),
			fileAvailable: z.boolean(),
			hasSolution: z.boolean(),
			id: z.string().min(1),
			language: z.string().min(2).max(8),
			resourceType: z.enum(RESOURCE_TYPES),
			reviewStatus: z.enum(REVIEW_STATUSES),
			rightsStatus: z.enum(RIGHTS_STATUSES),
			slug: slugSchema,
			tags: tagSchema,
			title: z.string().min(1),
			visibility: z.enum(RESOURCE_VISIBILITIES),
		})
		.strict(),
});

export const collections = {
	academicTerms,
	academicUnits,
	courses,
	curricula,
	curriculumCourses,
	resources,
};
