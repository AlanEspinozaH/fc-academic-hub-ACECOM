import { describe, expect, it } from 'vitest';
import { createSignInPageModel } from './sign-in-page';

describe('createSignInPageModel', () => {
	it('builds the anonymous sign-in page state with a validated next path', () => {
		const model = createSignInPageModel({
			authStatus: 'anonymous',
			rawError: null,
			rawNext: '/resources?course=cc#files',
		});

		expect(model).toEqual({
			authenticatedRedirect: null,
			errorCode: null,
			errorMessage: null,
			formAction: '/auth/google',
			isConfigured: true,
			next: '/resources?course=cc#files',
		});
	});

	it('redirects an authenticated user to a safe internal next path', () => {
		const model = createSignInPageModel({
			authStatus: 'authenticated',
			rawError: null,
			rawNext: '/courses?program=computacion',
		});

		expect(model.authenticatedRedirect).toBe('/courses?program=computacion');
	});

	it('falls back when an authenticated user provides an unsafe next path', () => {
		const model = createSignInPageModel({
			authStatus: 'authenticated',
			rawError: null,
			rawNext: 'https://evil.example/steal',
		});

		expect(model.authenticatedRedirect).toBe('/');
	});

	it('keeps the unconfigured page renderable with a controlled message', () => {
		const model = createSignInPageModel({
			authStatus: 'unconfigured',
			rawError: 'raw-google-error',
			rawNext: '/resources',
		});

		expect(model.errorCode).toBe('unconfigured');
		expect(model.errorMessage).toContain('acceso institucional');
		expect(model.isConfigured).toBe(false);
	});
});
