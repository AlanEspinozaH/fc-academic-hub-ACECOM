import { env } from 'cloudflare:workers';
import type { APIRoute } from 'astro';
import { createResourceFileUploadOrchestrator } from '../../../../application/resource-file-upload';
import { handleResourceFileUploadRequest } from '../../../../http/resource-file-upload-handler';
import { createMethodNotAllowedResponse } from '../../../../infrastructure/auth/http';
import { createR2ResourceObjectStore } from '../../../../infrastructure/r2/resource-object-store';
import { createSupabaseResourceUploadPersistence } from '../../../../infrastructure/supabase/resource-upload-persistence';
import type { SupabaseServerClient } from '../../../../infrastructure/supabase/server';

export const prerender = false;

const createUploader = (supabase: SupabaseServerClient) =>
	createResourceFileUploadOrchestrator(
		createSupabaseResourceUploadPersistence(supabase),
		createR2ResourceObjectStore(env.ACADEMIC_RESOURCES),
	);

export const POST: APIRoute = ({ locals, params, request }) =>
	handleResourceFileUploadRequest(
		{
			request,
			resourceId: params.resourceId,
			auth: locals.auth,
		},
		{
			createUploader,
		},
	);

export const ALL: APIRoute = () => createMethodNotAllowedResponse('POST');
