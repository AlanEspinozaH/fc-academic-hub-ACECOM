import { describe, expect, it } from 'vitest';
import { resolveSafeInternalRedirect, resolveSafePostAuthRedirect } from './redirects';

describe('resolveSafeInternalRedirect', () => {
	it('keeps safe internal path, query and fragment values', () => {
		expect(resolveSafeInternalRedirect('/courses?program=computacion#plan')).toBe(
			'/courses?program=computacion#plan',
		);
	});

	it('allows internal query and fragment values relative to the root path', () => {
		expect(resolveSafeInternalRedirect('?q=calculo#resultados')).toBe('/?q=calculo#resultados');
		expect(resolveSafeInternalRedirect('#contenido')).toBe('/#contenido');
	});

	it('uses the provided safe fallback for empty or malformed values', () => {
		expect(resolveSafeInternalRedirect('', '/resources')).toBe('/resources');
		expect(resolveSafeInternalRedirect('/courses/%', '/resources')).toBe('/resources');
		expect(resolveSafeInternalRedirect(null, '/resources')).toBe('/resources');
	});

	it.each([
		'https://evil.example/courses',
		'http://evil.example/courses',
		'javascript:alert(1)',
		'data:text/html,blocked',
		'//evil.example/courses',
		'/\\evil',
		'/%5cevil',
		'courses',
	])('rejects unsafe redirect value %s', (value) => {
		expect(resolveSafeInternalRedirect(value, '/')).toBe('/');
	});

	it('falls back to root when the fallback itself is unsafe', () => {
		expect(resolveSafeInternalRedirect('https://evil.example', 'https://other.example')).toBe('/');
	});
});

describe('resolveSafePostAuthRedirect', () => {
	it('keeps safe application destinations', () => {
		expect(resolveSafePostAuthRedirect('/resources?course=cc#files')).toBe(
			'/resources?course=cc#files',
		);
	});

	it.each([
		'/auth',
		'/auth/sign-in',
		'/AUTH/callback?code=loop',
		'/%61uth/sign-in',
		'/courses/../auth/sign-in',
	])('rejects authentication routes that could loop or re-enter the flow: %s', (value) => {
		expect(resolveSafePostAuthRedirect(value)).toBe('/');
	});

	it('rejects an authentication-route fallback', () => {
		expect(resolveSafePostAuthRedirect(null, '/auth/sign-in')).toBe('/');
	});
});
