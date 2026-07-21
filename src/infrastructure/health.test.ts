import { describe, expect, it } from 'vitest';
import packageJson from '../../package.json';
import { siteConfig } from '../config/site';
import { getHealthResponse } from './health';

describe('getHealthResponse', () => {
	it('returns the public service health payload', () => {
		expect(getHealthResponse()).toEqual({
			service: siteConfig.serviceName,
			status: 'ok',
			version: packageJson.version,
		});
	});
});
