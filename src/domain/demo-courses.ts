import type { AcademicTerm } from './academic-term';
import type { Course } from './course';

export const demoAcademicTerm: AcademicTerm = {
	id: 'demo-2026-1',
	label: 'Periodo ficticio 2026-I',
	season: 'first-semester',
	year: 2026,
};

export const demoCourses: ReadonlyArray<Course> = [
	{
		code: 'FC-DEMO-101',
		department: 'Departamento ficticio de Ciencias Integradas',
		id: 'demo-intro-ciencias-integradas',
		isDemo: true,
		level: 'undergraduate',
		summary:
			'Curso de demostracion sin materiales reales para validar la navegacion inicial del hub academico.',
		term: demoAcademicTerm,
		title: 'Introduccion Ficticia a las Ciencias Integradas',
	},
	{
		code: 'FC-DEMO-220',
		department: 'Departamento ficticio de Modelamiento',
		id: 'demo-taller-modelamiento',
		isDemo: true,
		level: 'undergraduate',
		summary:
			'Taller ficticio para representar futuros espacios de apuntes, examenes y silabos sin almacenar documentos.',
		term: demoAcademicTerm,
		title: 'Taller Ficticio de Modelamiento Cientifico',
	},
];
