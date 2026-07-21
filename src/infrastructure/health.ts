import packageJson from '../../package.json';
import { siteConfig } from '../config/site';

export interface HealthResponse {
	readonly service: typeof siteConfig.serviceName;
	readonly status: 'ok';
	readonly version: string;
}

export const getHealthResponse = (): HealthResponse => ({
	service: siteConfig.serviceName,
	status: 'ok',
	version: packageJson.version,
});
