import type { APIRoute } from 'astro';
import { getHealthResponse } from '../../infrastructure/health';

export const GET: APIRoute = () =>
	new Response(JSON.stringify(getHealthResponse()), {
		headers: {
			'cache-control': 'no-store',
			'content-type': 'application/json; charset=utf-8',
		},
	});
