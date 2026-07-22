import { describe, expect, it, vi } from 'vitest';
import { createProviderTokenRedactingFetch } from './provider-token-redaction';

const supabaseUrl = 'https://fc-academic-hub.supabase.co';

describe('createProviderTokenRedactingFetch', () => {
	it('removes provider tokens before a successful Auth token response reaches Supabase', async () => {
		const baseFetch = vi.fn<typeof fetch>(
			async () =>
				new Response(
					JSON.stringify({
						access_token: 'supabase-access-token',
						provider_token: 'google-access-token',
						provider_refresh_token: 'google-refresh-token',
						refresh_token: 'supabase-refresh-token',
						user: {
							raw_user_meta_data: {
								provider_token: 'nested-provider-token',
							},
						},
					}),
					{
						headers: {
							'content-length': '999',
							'content-type': 'application/json',
						},
						status: 200,
					},
				),
		);
		const safeFetch = createProviderTokenRedactingFetch(supabaseUrl, baseFetch);

		const response = await safeFetch(`${supabaseUrl}/auth/v1/token?grant_type=pkce`, {
			method: 'POST',
		});
		const payload = await response.json();
		const serializedPayload = JSON.stringify(payload);

		expect(payload).toMatchObject({
			access_token: 'supabase-access-token',
			refresh_token: 'supabase-refresh-token',
		});
		expect(serializedPayload).not.toContain('provider_token');
		expect(serializedPayload).not.toContain('provider_refresh_token');
		expect(serializedPayload).not.toContain('google-access-token');
		expect(serializedPayload).not.toContain('google-refresh-token');
		expect(response.headers.has('content-length')).toBe(false);
	});

	it('returns non-token endpoint responses without rewriting them', async () => {
		const originalResponse = Response.json({ provider_token: 'unchanged-outside-auth-token' });
		const baseFetch = vi.fn<typeof fetch>(async () => originalResponse);
		const safeFetch = createProviderTokenRedactingFetch(supabaseUrl, baseFetch);

		const response = await safeFetch(`${supabaseUrl}/rest/v1/courses`);

		expect(response).toBe(originalResponse);
	});

	it('does not replace failed Auth responses', async () => {
		const failedResponse = new Response('upstream failure', {
			status: 502,
		});
		const baseFetch = vi.fn<typeof fetch>(async () => failedResponse);
		const safeFetch = createProviderTokenRedactingFetch(supabaseUrl, baseFetch);

		const response = await safeFetch(`${supabaseUrl}/auth/v1/token?grant_type=pkce`, {
			method: 'POST',
		});

		expect(response).toBe(failedResponse);
	});

	it('does not replace successful non-JSON Auth responses', async () => {
		const nonJsonResponse = new Response('not-json', {
			headers: {
				'content-type': 'text/plain',
			},
			status: 200,
		});
		const baseFetch = vi.fn<typeof fetch>(async () => nonJsonResponse);
		const safeFetch = createProviderTokenRedactingFetch(supabaseUrl, baseFetch);

		const response = await safeFetch(`${supabaseUrl}/auth/v1/token?grant_type=pkce`, {
			method: 'POST',
		});

		expect(response).toBe(nonJsonResponse);
	});
});
