import type { AcademicUnit } from './academic-unit';
import type { Course } from './course';
import type { CurriculumCourse } from './curriculum-course';
import type { Curriculum } from './curriculum';

export interface CourseOffering {
	readonly curriculum: Curriculum;
	readonly curriculumCourse: CurriculumCourse;
	readonly faculty?: AcademicUnit;
	readonly program: AcademicUnit;
	readonly school?: AcademicUnit;
}

export interface CourseCatalogItem {
	readonly course: Course;
	readonly offerings: ReadonlyArray<CourseOffering>;
}
