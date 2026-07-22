import { resolveSafePostAuthRedirect } from './redirects';

export const signInErrorCodes = [
	'access_denied',
	'oauth_callback',
	'oauth_unavailable',
	'unconfigured',
] as const;

export type SignInErrorCode = (typeof signInErrorCodes)[number];

export type SignInAuthStatus = 'unconfigured' | 'anonymous' | 'authenticated' | 'error';

export interface SignInPageModel {
	readonly authenticatedRedirect: string | null;
	readonly errorCode: SignInErrorCode | null;
	readonly errorMessage: string | null;
	readonly formAction: '/auth/google';
	readonly isConfigured: boolean;
	readonly next: string;
}

const signInErrorMessages = {
	access_denied:
		'No pudimos confirmar una cuenta institucional habilitada. Intenta con tu correo institucional.',
	oauth_callback: 'No pudimos completar el acceso institucional. Vuelve a intentarlo.',
	oauth_unavailable: 'No pudimos iniciar el acceso institucional. Vuelve a intentarlo mas tarde.',
	unconfigured: 'El acceso institucional aun no esta configurado en este entorno.',
} satisfies Record<SignInErrorCode, string>;

const statusErrorCode = (status: SignInAuthStatus): SignInErrorCode | null => {
	if (status === 'unconfigured') {
		return 'unconfigured';
	}

	if (status === 'error') {
		return 'oauth_unavailable';
	}

	return null;
};

export const resolveSignInErrorCode = (
	value: string | null | undefined,
): SignInErrorCode | null => {
	if (typeof value !== 'string') {
		return null;
	}

	const normalizedValue = value.trim();

	return signInErrorCodes.find((code) => code === normalizedValue) ?? null;
};

export const createSignInPageModel = ({
	authStatus,
	rawError,
	rawNext,
}: {
	readonly authStatus: SignInAuthStatus;
	readonly rawError: string | null | undefined;
	readonly rawNext: string | null | undefined;
}): SignInPageModel => {
	const next = resolveSafePostAuthRedirect(rawNext);
	const errorCode = statusErrorCode(authStatus) ?? resolveSignInErrorCode(rawError);

	return {
		authenticatedRedirect: authStatus === 'authenticated' ? next : null,
		errorCode,
		errorMessage: errorCode ? signInErrorMessages[errorCode] : null,
		formAction: '/auth/google',
		isConfigured: authStatus !== 'unconfigured',
		next,
	};
};
