export type AcademicTermSeason = 'summer' | 'first-semester' | 'second-semester';

export interface AcademicTerm {
	readonly id: string;
	readonly label: string;
	readonly season: AcademicTermSeason;
	readonly year: number;
}
