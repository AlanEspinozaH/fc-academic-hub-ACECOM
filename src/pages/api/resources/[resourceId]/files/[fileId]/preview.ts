import { env } from 'cloudflare:workers';
import type { APIRoute } from 'astro';
import { createResourceFileReader } from '../../../../../../application/resource-file-read';
import { handleResourceFileReadRequest } from '../../../../../../http/resource-file-read-handler';
import { createMethodNotAllowedResponse } from '../../../../../../infrastructure/auth/http';
import { createR2ResourceObjectStore } from '../../../../../../infrastructure/r2/resource-object-store';
import { createSupabaseResourceFileReadPersistence } from '../../../../../../infrastructure/supabase/resource-file-read-persistence';
import type { SupabaseServerClient } from '../../../../../../infrastructure/supabase/server';

export const prerender = false;

const createReader = (supabase: SupabaseServerClient) =>
	createResourceFileReader(
		createSupabaseResourceFileReadPersistence(supabase),
		createR2ResourceObjectStore(env.ACADEMIC_RESOURCES),
	);

export const GET: APIRoute = ({ locals, params, request }) =>
	handleResourceFileReadRequest(
		{
			request,
			resourceId: params.resourceId,
			fileId: params.fileId,
			disposition: 'inline',
			auth: locals.auth,
		},
		{ createReader },
	);

export const ALL: APIRoute = () => createMethodNotAllowedResponse('GET');
