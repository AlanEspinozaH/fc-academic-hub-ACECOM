export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

export type Database = {
	public: {
		Tables: {
			academic_resources: {
				Row: {
					academic_term_id: string | null;
					course_id: string;
					created_at: string;
					description: string;
					has_solution: boolean;
					id: string;
					language: string;
					owner_user_id: string;
					resource_type: string;
					review_status: Database['public']['Enums']['resource_review_status'];
					reviewed_at: string | null;
					reviewed_by: string | null;
					rights_notes: string | null;
					rights_status: Database['public']['Enums']['resource_rights_status'];
					submitted_at: string | null;
					tags: string[];
					title: string;
					updated_at: string;
					visibility: Database['public']['Enums']['resource_visibility'];
				};
				Insert: {
					academic_term_id?: string | null;
					course_id: string;
					created_at?: string;
					description: string;
					has_solution?: boolean;
					id?: string;
					language?: string;
					owner_user_id: string;
					resource_type: string;
					review_status?: Database['public']['Enums']['resource_review_status'];
					reviewed_at?: string | null;
					reviewed_by?: string | null;
					rights_notes?: string | null;
					rights_status?: Database['public']['Enums']['resource_rights_status'];
					submitted_at?: string | null;
					tags?: string[];
					title: string;
					updated_at?: string;
					visibility?: Database['public']['Enums']['resource_visibility'];
				};
				Update: {
					academic_term_id?: string | null;
					course_id?: string;
					created_at?: string;
					description?: string;
					has_solution?: boolean;
					id?: string;
					language?: string;
					owner_user_id?: string;
					resource_type?: string;
					review_status?: Database['public']['Enums']['resource_review_status'];
					reviewed_at?: string | null;
					reviewed_by?: string | null;
					rights_notes?: string | null;
					rights_status?: Database['public']['Enums']['resource_rights_status'];
					submitted_at?: string | null;
					tags?: string[];
					title?: string;
					updated_at?: string;
					visibility?: Database['public']['Enums']['resource_visibility'];
				};
				Relationships: [
					{
						foreignKeyName: 'academic_resources_owner_user_id_fkey';
						columns: ['owner_user_id'];
						isOneToOne: false;
						referencedRelation: 'profiles';
						referencedColumns: ['user_id'];
					},
					{
						foreignKeyName: 'academic_resources_reviewed_by_fkey';
						columns: ['reviewed_by'];
						isOneToOne: false;
						referencedRelation: 'profiles';
						referencedColumns: ['user_id'];
					},
				];
			};
			allowed_email_domains: {
				Row: {
					created_at: string;
					created_by: string | null;
					domain: string;
					enabled: boolean;
				};
				Insert: {
					created_at?: string;
					created_by?: string | null;
					domain: string;
					enabled?: boolean;
				};
				Update: {
					created_at?: string;
					created_by?: string | null;
					domain?: string;
					enabled?: boolean;
				};
				Relationships: [];
			};
			profiles: {
				Row: {
					account_status: Database['public']['Enums']['account_status'];
					created_at: string;
					display_name: string | null;
					email: string;
					updated_at: string;
					user_id: string;
				};
				Insert: {
					account_status?: Database['public']['Enums']['account_status'];
					created_at?: string;
					display_name?: string | null;
					email: string;
					updated_at?: string;
					user_id: string;
				};
				Update: {
					account_status?: Database['public']['Enums']['account_status'];
					created_at?: string;
					display_name?: string | null;
					email?: string;
					updated_at?: string;
					user_id?: string;
				};
				Relationships: [];
			};
			resource_files: {
				Row: {
					byte_size: number;
					content_type: string;
					created_at: string;
					display_filename: string;
					id: string;
					resource_id: string;
					sha256: string | null;
					updated_at: string;
					uploaded_by: string;
				};
				Insert: {
					byte_size: number;
					content_type: string;
					created_at?: string;
					display_filename: string;
					id?: string;
					resource_id: string;
					sha256?: string | null;
					updated_at?: string;
					uploaded_by: string;
				};
				Update: {
					byte_size?: number;
					content_type?: string;
					created_at?: string;
					display_filename?: string;
					id?: string;
					resource_id?: string;
					sha256?: string | null;
					updated_at?: string;
					uploaded_by?: string;
				};
				Relationships: [
					{
						foreignKeyName: 'resource_files_resource_id_fkey';
						columns: ['resource_id'];
						isOneToOne: true;
						referencedRelation: 'academic_resources';
						referencedColumns: ['id'];
					},
					{
						foreignKeyName: 'resource_files_uploaded_by_fkey';
						columns: ['uploaded_by'];
						isOneToOne: false;
						referencedRelation: 'profiles';
						referencedColumns: ['user_id'];
					},
				];
			};
			resource_review_events: {
				Row: {
					action: string;
					actor_user_id: string;
					comment: string | null;
					from_status: Database['public']['Enums']['resource_review_status'] | null;
					id: number;
					metadata: Json;
					occurred_at: string;
					resource_id: string;
					to_status: Database['public']['Enums']['resource_review_status'];
				};
				Insert: {
					action: string;
					actor_user_id: string;
					comment?: string | null;
					from_status?: Database['public']['Enums']['resource_review_status'] | null;
					id?: never;
					metadata?: Json;
					occurred_at?: string;
					resource_id: string;
					to_status: Database['public']['Enums']['resource_review_status'];
				};
				Update: {
					action?: string;
					actor_user_id?: string;
					comment?: string | null;
					from_status?: Database['public']['Enums']['resource_review_status'] | null;
					id?: never;
					metadata?: Json;
					occurred_at?: string;
					resource_id?: string;
					to_status?: Database['public']['Enums']['resource_review_status'];
				};
				Relationships: [
					{
						foreignKeyName: 'resource_review_events_actor_user_id_fkey';
						columns: ['actor_user_id'];
						isOneToOne: false;
						referencedRelation: 'profiles';
						referencedColumns: ['user_id'];
					},
					{
						foreignKeyName: 'resource_review_events_resource_id_fkey';
						columns: ['resource_id'];
						isOneToOne: false;
						referencedRelation: 'academic_resources';
						referencedColumns: ['id'];
					},
				];
			};
			role_audit_log: {
				Row: {
					action: string;
					actor_user_id: string;
					id: number;
					metadata: Json;
					occurred_at: string;
					role: Database['public']['Enums']['app_role'];
					target_user_id: string;
				};
				Insert: {
					action: string;
					actor_user_id: string;
					id?: never;
					metadata?: Json;
					occurred_at?: string;
					role: Database['public']['Enums']['app_role'];
					target_user_id: string;
				};
				Update: {
					action?: string;
					actor_user_id?: string;
					id?: never;
					metadata?: Json;
					occurred_at?: string;
					role?: Database['public']['Enums']['app_role'];
					target_user_id?: string;
				};
				Relationships: [
					{
						foreignKeyName: 'role_audit_log_actor_user_id_fkey';
						columns: ['actor_user_id'];
						isOneToOne: false;
						referencedRelation: 'profiles';
						referencedColumns: ['user_id'];
					},
					{
						foreignKeyName: 'role_audit_log_target_user_id_fkey';
						columns: ['target_user_id'];
						isOneToOne: false;
						referencedRelation: 'profiles';
						referencedColumns: ['user_id'];
					},
				];
			};
			user_roles: {
				Row: {
					granted_at: string;
					granted_by: string;
					id: number;
					reason: string | null;
					revoked_at: string | null;
					revoked_by: string | null;
					role: Database['public']['Enums']['app_role'];
					user_id: string;
				};
				Insert: {
					granted_at?: string;
					granted_by: string;
					id?: never;
					reason?: string | null;
					revoked_at?: string | null;
					revoked_by?: string | null;
					role: Database['public']['Enums']['app_role'];
					user_id: string;
				};
				Update: {
					granted_at?: string;
					granted_by?: string;
					id?: never;
					reason?: string | null;
					revoked_at?: string | null;
					revoked_by?: string | null;
					role?: Database['public']['Enums']['app_role'];
					user_id?: string;
				};
				Relationships: [
					{
						foreignKeyName: 'user_roles_granted_by_fkey';
						columns: ['granted_by'];
						isOneToOne: false;
						referencedRelation: 'profiles';
						referencedColumns: ['user_id'];
					},
					{
						foreignKeyName: 'user_roles_revoked_by_fkey';
						columns: ['revoked_by'];
						isOneToOne: false;
						referencedRelation: 'profiles';
						referencedColumns: ['user_id'];
					},
					{
						foreignKeyName: 'user_roles_user_id_fkey';
						columns: ['user_id'];
						isOneToOne: false;
						referencedRelation: 'profiles';
						referencedColumns: ['user_id'];
					},
				];
			};
		};
		Views: {
			[_ in never]: never;
		};
		Functions: {
			abort_resource_file_upload: {
				Args: { file_id: string; reason?: string };
				Returns: string;
			};
			approve_academic_resource: {
				Args: { comment?: string; resource_id: string };
				Returns: number;
			};
			finalize_resource_file_upload: {
				Args: { comment?: string; file_id: string; sha256: string };
				Returns: string;
			};
			grant_user_role: {
				Args: {
					reason?: string;
					role: Database['public']['Enums']['app_role'];
					target_user_id: string;
				};
				Returns: number;
			};
			mark_resource_file_failed: {
				Args: { file_id: string; reason?: string };
				Returns: string;
			};
			mark_resource_file_stored: {
				Args: { file_id: string; sha256?: string };
				Returns: string;
			};
			register_resource_file_upload: {
				Args: {
					byte_size: number;
					content_type: string;
					display_filename: string;
					resource_id: string;
					sha256?: string;
				};
				Returns: string;
			};
			reject_academic_resource: {
				Args: { comment?: string; resource_id: string };
				Returns: number;
			};
			revoke_user_role: {
				Args: {
					reason?: string;
					role: Database['public']['Enums']['app_role'];
					target_user_id: string;
				};
				Returns: number;
			};
			submit_academic_resource: {
				Args: { comment?: string; resource_id: string };
				Returns: number;
			};
		};
		Enums: {
			account_status: 'active' | 'suspended' | 'disabled';
			app_role: 'student' | 'contributor' | 'reviewer' | 'moderator' | 'administrator';
			resource_review_status: 'draft' | 'pending' | 'approved' | 'rejected';
			resource_rights_status:
				| 'pending'
				| 'own-work'
				| 'authorized'
				| 'institutional'
				| 'bibliographic-reference-only'
				| 'copyright-restricted';
			resource_storage_status: 'uploading' | 'stored' | 'delete_pending' | 'deleted' | 'failed';
			resource_visibility: 'private' | 'restricted' | 'public';
		};
		CompositeTypes: {
			[_ in never]: never;
		};
	};
};

type DatabaseWithoutInternals = Omit<Database, '__InternalSupabase'>;

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, 'public'>];

export type Tables<
	DefaultSchemaTableNameOrOptions extends
		| keyof (DefaultSchema['Tables'] & DefaultSchema['Views'])
		| { schema: keyof DatabaseWithoutInternals },
	TableName extends (DefaultSchemaTableNameOrOptions extends {
		schema: keyof DatabaseWithoutInternals;
	}
		? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'] &
				DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Views'])
		: never) = never,
> = DefaultSchemaTableNameOrOptions extends {
	schema: keyof DatabaseWithoutInternals;
}
	? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'] &
			DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Views'])[TableName] extends {
			Row: infer R;
		}
		? R
		: never
	: DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema['Tables'] & DefaultSchema['Views'])
		? (DefaultSchema['Tables'] & DefaultSchema['Views'])[DefaultSchemaTableNameOrOptions] extends {
				Row: infer R;
			}
			? R
			: never
		: never;

export type TablesInsert<
	DefaultSchemaTableNameOrOptions extends
		keyof DefaultSchema['Tables'] | { schema: keyof DatabaseWithoutInternals },
	TableName extends (DefaultSchemaTableNameOrOptions extends {
		schema: keyof DatabaseWithoutInternals;
	}
		? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables']
		: never) = never,
> = DefaultSchemaTableNameOrOptions extends {
	schema: keyof DatabaseWithoutInternals;
}
	? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'][TableName] extends {
			Insert: infer I;
		}
		? I
		: never
	: DefaultSchemaTableNameOrOptions extends keyof DefaultSchema['Tables']
		? DefaultSchema['Tables'][DefaultSchemaTableNameOrOptions] extends {
				Insert: infer I;
			}
			? I
			: never
		: never;

export type TablesUpdate<
	DefaultSchemaTableNameOrOptions extends
		keyof DefaultSchema['Tables'] | { schema: keyof DatabaseWithoutInternals },
	TableName extends (DefaultSchemaTableNameOrOptions extends {
		schema: keyof DatabaseWithoutInternals;
	}
		? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables']
		: never) = never,
> = DefaultSchemaTableNameOrOptions extends {
	schema: keyof DatabaseWithoutInternals;
}
	? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions['schema']]['Tables'][TableName] extends {
			Update: infer U;
		}
		? U
		: never
	: DefaultSchemaTableNameOrOptions extends keyof DefaultSchema['Tables']
		? DefaultSchema['Tables'][DefaultSchemaTableNameOrOptions] extends {
				Update: infer U;
			}
			? U
			: never
		: never;

export type Enums<
	DefaultSchemaEnumNameOrOptions extends
		keyof DefaultSchema['Enums'] | { schema: keyof DatabaseWithoutInternals },
	EnumName extends (DefaultSchemaEnumNameOrOptions extends {
		schema: keyof DatabaseWithoutInternals;
	}
		? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions['schema']]['Enums']
		: never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
	schema: keyof DatabaseWithoutInternals;
}
	? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions['schema']]['Enums'][EnumName]
	: DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema['Enums']
		? DefaultSchema['Enums'][DefaultSchemaEnumNameOrOptions]
		: never;

export type CompositeTypes<
	PublicCompositeTypeNameOrOptions extends
		keyof DefaultSchema['CompositeTypes'] | { schema: keyof DatabaseWithoutInternals },
	CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
		schema: keyof DatabaseWithoutInternals;
	}
		? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions['schema']]['CompositeTypes']
		: never) = never,
> = PublicCompositeTypeNameOrOptions extends {
	schema: keyof DatabaseWithoutInternals;
}
	? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions['schema']]['CompositeTypes'][CompositeTypeName]
	: PublicCompositeTypeNameOrOptions extends keyof DefaultSchema['CompositeTypes']
		? DefaultSchema['CompositeTypes'][PublicCompositeTypeNameOrOptions]
		: never;

export const Constants = {
	public: {
		Enums: {
			account_status: ['active', 'suspended', 'disabled'],
			app_role: ['student', 'contributor', 'reviewer', 'moderator', 'administrator'],
			resource_review_status: ['draft', 'pending', 'approved', 'rejected'],
			resource_rights_status: [
				'pending',
				'own-work',
				'authorized',
				'institutional',
				'bibliographic-reference-only',
				'copyright-restricted',
			],
			resource_storage_status: ['uploading', 'stored', 'delete_pending', 'deleted', 'failed'],
			resource_visibility: ['private', 'restricted', 'public'],
		},
	},
} as const;
