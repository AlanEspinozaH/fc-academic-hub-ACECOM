import { describe, expect, it, vi } from 'vitest';
import { clearInheritedUrlFragment } from './browser-url';

describe('clearInheritedUrlFragment', () => {
	it('does nothing when the URL has no fragment', () => {
		const replaceUrl = vi.fn();

		const changed = clearInheritedUrlFragment({
			hash: '',
			pathname: '/auth/sign-in',
			search: '?error=access_denied',
			replaceUrl,
		});

		expect(changed).toBe(false);
		expect(replaceUrl).not.toHaveBeenCalled();
	});

	it('removes the fragment while preserving path and query', () => {
		const replaceUrl = vi.fn();

		const changed = clearInheritedUrlFragment({
			hash: '#error=server_error&error_description=internal-detail',
			pathname: '/auth/sign-in',
			search: '?error=access_denied&next=%2F',
			replaceUrl,
		});

		expect(changed).toBe(true);
		expect(replaceUrl).toHaveBeenCalledWith('/auth/sign-in?error=access_denied&next=%2F');
	});

	it('does not propagate provider error details', () => {
		const replaceUrl = vi.fn();

		clearInheritedUrlFragment({
			hash: '#error_description=Database+error+saving+new+user',
			pathname: '/auth/sign-in',
			search: '',
			replaceUrl,
		});

		const replacement = replaceUrl.mock.calls[0]?.[0];

		expect(replacement).toBe('/auth/sign-in');
		expect(replacement).not.toContain('Database');
		expect(replacement).not.toContain('error_description');
	});
});
