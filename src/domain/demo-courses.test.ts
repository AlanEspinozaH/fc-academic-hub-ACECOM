import { describe, expect, it } from 'vitest';
import { demoAcademicTerm, demoCourses } from './demo-courses';

describe('demoCourses', () => {
	it('contains exactly two clearly marked fictitious courses', () => {
		expect(demoCourses).toHaveLength(2);
		expect(demoCourses.every((course) => course.isDemo)).toBe(true);
		expect(demoCourses.every((course) => course.code.startsWith('FC-DEMO-'))).toBe(true);
		expect(
			demoCourses.every((course) => /fictici|demostracion/i.test(course.title + course.summary)),
		).toBe(true);
	});

	it('uses a shared fictitious academic term for stage 1 data', () => {
		expect(demoAcademicTerm.id).toBe('demo-2026-1');
		expect(demoAcademicTerm.label.toLowerCase()).toContain('ficticio');
		expect(demoCourses.every((course) => course.term === demoAcademicTerm)).toBe(true);
	});
});
