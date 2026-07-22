export interface BrowserUrlContext {
	readonly hash: string;
	readonly pathname: string;
	readonly search: string;
	readonly replaceUrl: (url: string) => void;
}

export const clearInheritedUrlFragment = (context: BrowserUrlContext): boolean => {
	if (!context.hash) {
		return false;
	}

	context.replaceUrl(`${context.pathname}${context.search}`);
	return true;
};
