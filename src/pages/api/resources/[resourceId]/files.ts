import { env } from 'cloudflare:workers';
import type { APIRoute } from 'astro';
import { createResourcePdfUploadOrchestrator } from '../../../../application/resource-pdf-upload';
import { handleResourcePdfUploadRequest } from '../../../../http/resource-pdf-upload-handler';
import { createMethodNotAllowedResponse } from '../../../../infrastructure/auth/http';
import { createR2ResourceObjectStore } from '../../../../infrastructure/r2/resource-object-store';
import { createSupabaseResourceUploadPersistence } from '../../../../infrastructure/supabase/resource-upload-persistence';
import type { SupabaseServerClient } from '../../../../infrastructure/supabase/server';

export const prerender = false;

const createUploader = (supabase: SupabaseServerClient) =>
	createResourcePdfUploadOrchestrator(
		createSupabaseResourceUploadPersistence(supabase),
		createR2ResourceObjectStore(env.ACADEMIC_RESOURCES),
	);

export const POST: APIRoute = ({ locals, params, request }) =>
	handleResourcePdfUploadRequest(
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
