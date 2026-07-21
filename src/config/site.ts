export const siteConfig = {
	name: 'FC Academic Hub',
	serviceName: 'fc-academic-hub',
	description:
		'Plataforma academica comunitaria para organizar cursos, examenes, apuntes, silabos y recursos de la Facultad de Ciencias.',
	locale: 'es',
	stage: 'Etapa 1',
	navigation: [
		{ href: '/', label: 'Inicio' },
		{ href: '/courses', label: 'Cursos' },
		{ href: '/about', label: 'Acerca de' },
	],
} as const;

export type SiteNavigationItem = (typeof siteConfig.navigation)[number];
