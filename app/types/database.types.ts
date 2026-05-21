export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      attachments: {
        Row: {
          content_id: string | null
          created_at: string | null
          file_size: number | null
          file_type: string | null
          file_url: string
          id: string
          name: string
        }
        Insert: {
          content_id?: string | null
          created_at?: string | null
          file_size?: number | null
          file_type?: string | null
          file_url: string
          id?: string
          name: string
        }
        Update: {
          content_id?: string | null
          created_at?: string | null
          file_size?: number | null
          file_type?: string | null
          file_url?: string
          id?: string
          name?: string
        }
        Relationships: [
          {
            foreignKeyName: "attachments_content_id_fkey"
            columns: ["content_id"]
            isOneToOne: false
            referencedRelation: "contents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "attachments_content_id_fkey"
            columns: ["content_id"]
            isOneToOne: false
            referencedRelation: "course_structure"
            referencedColumns: ["content_id"]
          },
        ]
      }
      badges: {
        Row: {
          condition_type: string
          condition_value: number
          description: string
          icon_url: string | null
          id: string
          name: string
          slug: string
        }
        Insert: {
          condition_type: string
          condition_value: number
          description: string
          icon_url?: string | null
          id?: string
          name: string
          slug: string
        }
        Update: {
          condition_type?: string
          condition_value?: number
          description?: string
          icon_url?: string | null
          id?: string
          name?: string
          slug?: string
        }
        Relationships: []
      }
      comments: {
        Row: {
          comment_text: string
          content_id: string
          created_at: string
          id: string
          parent_id: string | null
          user_id: string
        }
        Insert: {
          comment_text: string
          content_id: string
          created_at?: string
          id?: string
          parent_id?: string | null
          user_id?: string
        }
        Update: {
          comment_text?: string
          content_id?: string
          created_at?: string
          id?: string
          parent_id?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "comments_content_id_fkey"
            columns: ["content_id"]
            isOneToOne: false
            referencedRelation: "contents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "comments_content_id_fkey"
            columns: ["content_id"]
            isOneToOne: false
            referencedRelation: "course_structure"
            referencedColumns: ["content_id"]
          },
          {
            foreignKeyName: "comments_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "comments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "comments_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "content_comments_view"
            referencedColumns: ["comment_id"]
          },
        ]
      }
      content_chunks: {
        Row: {
          chunk_index: number
          content_id: string
          created_at: string
          embedding: string | null
          embedding_model: string
          end_time: number
          id: string
          start_time: number
          text: string
          token_count: number | null
        }
        Insert: {
          chunk_index: number
          content_id: string
          created_at?: string
          embedding?: string | null
          embedding_model?: string
          end_time: number
          id?: string
          start_time: number
          text: string
          token_count?: number | null
        }
        Update: {
          chunk_index?: number
          content_id?: string
          created_at?: string
          embedding?: string | null
          embedding_model?: string
          end_time?: number
          id?: string
          start_time?: number
          text?: string
          token_count?: number | null
        }
        Relationships: [
          {
            foreignKeyName: "content_chunks_content_id_fkey"
            columns: ["content_id"]
            isOneToOne: false
            referencedRelation: "contents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "content_chunks_content_id_fkey"
            columns: ["content_id"]
            isOneToOne: false
            referencedRelation: "course_structure"
            referencedColumns: ["content_id"]
          },
        ]
      }
      content_transcriptions: {
        Row: {
          content_id: string
          created_at: string
          duration_sec: number | null
          full_text: string
          language: string | null
          model: string
          segments_json: Json
        }
        Insert: {
          content_id: string
          created_at?: string
          duration_sec?: number | null
          full_text: string
          language?: string | null
          model: string
          segments_json: Json
        }
        Update: {
          content_id?: string
          created_at?: string
          duration_sec?: number | null
          full_text?: string
          language?: string | null
          model?: string
          segments_json?: Json
        }
        Relationships: [
          {
            foreignKeyName: "content_transcriptions_content_id_fkey"
            columns: ["content_id"]
            isOneToOne: true
            referencedRelation: "contents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "content_transcriptions_content_id_fkey"
            columns: ["content_id"]
            isOneToOne: true
            referencedRelation: "course_structure"
            referencedColumns: ["content_id"]
          },
        ]
      }
      contents: {
        Row: {
          body_text: string | null
          content_type: string
          created_at: string
          duration: number | null
          file_url: string | null
          id: string
          module_id: string
          order_index: number | null
          status: string | null
          thumbnail_url: string | null
          title: string
          video_url: string | null
        }
        Insert: {
          body_text?: string | null
          content_type: string
          created_at?: string
          duration?: number | null
          file_url?: string | null
          id?: string
          module_id: string
          order_index?: number | null
          status?: string | null
          thumbnail_url?: string | null
          title: string
          video_url?: string | null
        }
        Update: {
          body_text?: string | null
          content_type?: string
          created_at?: string
          duration?: number | null
          file_url?: string | null
          id?: string
          module_id?: string
          order_index?: number | null
          status?: string | null
          thumbnail_url?: string | null
          title?: string
          video_url?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "contents_module_id_fkey"
            columns: ["module_id"]
            isOneToOne: false
            referencedRelation: "course_structure"
            referencedColumns: ["module_id"]
          },
          {
            foreignKeyName: "contents_module_id_fkey"
            columns: ["module_id"]
            isOneToOne: false
            referencedRelation: "modules"
            referencedColumns: ["id"]
          },
        ]
      }
      courses: {
        Row: {
          created_at: string
          description: string | null
          id: string
          thumbnail_url: string | null
          title: string
        }
        Insert: {
          created_at?: string
          description?: string | null
          id?: string
          thumbnail_url?: string | null
          title: string
        }
        Update: {
          created_at?: string
          description?: string | null
          id?: string
          thumbnail_url?: string | null
          title?: string
        }
        Relationships: []
      }
      group_course_access: {
        Row: {
          course_id: string
          group_id: string
        }
        Insert: {
          course_id: string
          group_id: string
        }
        Update: {
          course_id?: string
          group_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "group_course_access_course_id_fkey"
            columns: ["course_id"]
            isOneToOne: false
            referencedRelation: "course_catalog"
            referencedColumns: ["course_id"]
          },
          {
            foreignKeyName: "group_course_access_course_id_fkey"
            columns: ["course_id"]
            isOneToOne: false
            referencedRelation: "course_structure"
            referencedColumns: ["course_id"]
          },
          {
            foreignKeyName: "group_course_access_course_id_fkey"
            columns: ["course_id"]
            isOneToOne: false
            referencedRelation: "courses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "group_course_access_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: false
            referencedRelation: "permission_groups"
            referencedColumns: ["id"]
          },
        ]
      }
      modules: {
        Row: {
          course_id: string
          created_at: string
          id: string
          order_index: number | null
          title: string
        }
        Insert: {
          course_id: string
          created_at?: string
          id?: string
          order_index?: number | null
          title: string
        }
        Update: {
          course_id?: string
          created_at?: string
          id?: string
          order_index?: number | null
          title?: string
        }
        Relationships: [
          {
            foreignKeyName: "modules_course_id_fkey"
            columns: ["course_id"]
            isOneToOne: false
            referencedRelation: "course_catalog"
            referencedColumns: ["course_id"]
          },
          {
            foreignKeyName: "modules_course_id_fkey"
            columns: ["course_id"]
            isOneToOne: false
            referencedRelation: "course_structure"
            referencedColumns: ["course_id"]
          },
          {
            foreignKeyName: "modules_course_id_fkey"
            columns: ["course_id"]
            isOneToOne: false
            referencedRelation: "courses"
            referencedColumns: ["id"]
          },
        ]
      }
      perfis: {
        Row: {
          avatar_url: string | null
          created_at: string
          email: string | null
          id: string
          name: string
          role: string
        }
        Insert: {
          avatar_url?: string | null
          created_at?: string
          email?: string | null
          id: string
          name: string
          role?: string
        }
        Update: {
          avatar_url?: string | null
          created_at?: string
          email?: string | null
          id?: string
          name?: string
          role?: string
        }
        Relationships: []
      }
      permission_groups: {
        Row: {
          created_at: string
          description: string | null
          id: string
          name: string
        }
        Insert: {
          created_at?: string
          description?: string | null
          id?: string
          name: string
        }
        Update: {
          created_at?: string
          description?: string | null
          id?: string
          name?: string
        }
        Relationships: []
      }
      point_events: {
        Row: {
          created_at: string | null
          event_type: string
          group_id: string
          id: string
          points: number
          reference_id: string
          user_id: string
        }
        Insert: {
          created_at?: string | null
          event_type: string
          group_id: string
          id?: string
          points: number
          reference_id: string
          user_id: string
        }
        Update: {
          created_at?: string | null
          event_type?: string
          group_id?: string
          id?: string
          points?: number
          reference_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "point_events_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: false
            referencedRelation: "permission_groups"
            referencedColumns: ["id"]
          },
        ]
      }
      point_rules: {
        Row: {
          event_type: string
          id: string
          is_active: boolean | null
          points: number
        }
        Insert: {
          event_type: string
          id?: string
          is_active?: boolean | null
          points: number
        }
        Update: {
          event_type?: string
          id?: string
          is_active?: boolean | null
          points?: number
        }
        Relationships: []
      }
      private_notes: {
        Row: {
          content_id: string
          id: string
          note_text: string
          updated_at: string
          user_id: string
        }
        Insert: {
          content_id: string
          id?: string
          note_text: string
          updated_at?: string
          user_id?: string
        }
        Update: {
          content_id?: string
          id?: string
          note_text?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "private_notes_content_id_fkey"
            columns: ["content_id"]
            isOneToOne: false
            referencedRelation: "contents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "private_notes_content_id_fkey"
            columns: ["content_id"]
            isOneToOne: false
            referencedRelation: "course_structure"
            referencedColumns: ["content_id"]
          },
        ]
      }
      user_access_mode: {
        Row: {
          mode: string
          user_id: string
        }
        Insert: {
          mode?: string
          user_id: string
        }
        Update: {
          mode?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_access_mode_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: true
            referencedRelation: "perfis"
            referencedColumns: ["id"]
          },
        ]
      }
      user_badges: {
        Row: {
          badge_id: string
          earned_at: string | null
          id: string
          user_id: string
        }
        Insert: {
          badge_id: string
          earned_at?: string | null
          id?: string
          user_id: string
        }
        Update: {
          badge_id?: string
          earned_at?: string | null
          id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_badges_badge_id_fkey"
            columns: ["badge_id"]
            isOneToOne: false
            referencedRelation: "badges"
            referencedColumns: ["id"]
          },
        ]
      }
      user_course_access: {
        Row: {
          course_id: string
          user_id: string
        }
        Insert: {
          course_id: string
          user_id: string
        }
        Update: {
          course_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_course_access_course_id_fkey"
            columns: ["course_id"]
            isOneToOne: false
            referencedRelation: "course_catalog"
            referencedColumns: ["course_id"]
          },
          {
            foreignKeyName: "user_course_access_course_id_fkey"
            columns: ["course_id"]
            isOneToOne: false
            referencedRelation: "course_structure"
            referencedColumns: ["course_id"]
          },
          {
            foreignKeyName: "user_course_access_course_id_fkey"
            columns: ["course_id"]
            isOneToOne: false
            referencedRelation: "courses"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_course_access_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "perfis"
            referencedColumns: ["id"]
          },
        ]
      }
      user_groups: {
        Row: {
          group_id: string
          user_id: string
        }
        Insert: {
          group_id: string
          user_id: string
        }
        Update: {
          group_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_groups_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: false
            referencedRelation: "permission_groups"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_groups_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "perfis"
            referencedColumns: ["id"]
          },
        ]
      }
      user_points: {
        Row: {
          group_id: string
          id: string
          total_points: number
          updated_at: string | null
          user_id: string
        }
        Insert: {
          group_id: string
          id?: string
          total_points?: number
          updated_at?: string | null
          user_id: string
        }
        Update: {
          group_id?: string
          id?: string
          total_points?: number
          updated_at?: string | null
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_points_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: false
            referencedRelation: "permission_groups"
            referencedColumns: ["id"]
          },
        ]
      }
      user_progress: {
        Row: {
          completed_at: string | null
          content_id: string
          user_id: string
        }
        Insert: {
          completed_at?: string | null
          content_id: string
          user_id?: string
        }
        Update: {
          completed_at?: string | null
          content_id?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_progress_content_id_fkey"
            columns: ["content_id"]
            isOneToOne: false
            referencedRelation: "contents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_progress_content_id_fkey"
            columns: ["content_id"]
            isOneToOne: false
            referencedRelation: "course_structure"
            referencedColumns: ["content_id"]
          },
        ]
      }
      user_streaks: {
        Row: {
          current_streak: number
          last_activity_date: string | null
          updated_at: string | null
          user_id: string
        }
        Insert: {
          current_streak?: number
          last_activity_date?: string | null
          updated_at?: string | null
          user_id: string
        }
        Update: {
          current_streak?: number
          last_activity_date?: string | null
          updated_at?: string | null
          user_id?: string
        }
        Relationships: []
      }
    }
    Views: {
      content_comments_view: {
        Row: {
          comment_id: string | null
          comment_text: string | null
          content_id: string | null
          created_at: string | null
          parent_id: string | null
          user_id: string | null
          user_name: string | null
        }
        Relationships: [
          {
            foreignKeyName: "comments_content_id_fkey"
            columns: ["content_id"]
            isOneToOne: false
            referencedRelation: "contents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "comments_content_id_fkey"
            columns: ["content_id"]
            isOneToOne: false
            referencedRelation: "course_structure"
            referencedColumns: ["content_id"]
          },
          {
            foreignKeyName: "comments_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "comments"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "comments_parent_id_fkey"
            columns: ["parent_id"]
            isOneToOne: false
            referencedRelation: "content_comments_view"
            referencedColumns: ["comment_id"]
          },
        ]
      }
      content_private_notes_view: {
        Row: {
          content_id: string | null
          note_id: string | null
          note_text: string | null
          updated_at: string | null
          user_id: string | null
        }
        Insert: {
          content_id?: string | null
          note_id?: string | null
          note_text?: string | null
          updated_at?: string | null
          user_id?: string | null
        }
        Update: {
          content_id?: string | null
          note_id?: string | null
          note_text?: string | null
          updated_at?: string | null
          user_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "private_notes_content_id_fkey"
            columns: ["content_id"]
            isOneToOne: false
            referencedRelation: "contents"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "private_notes_content_id_fkey"
            columns: ["content_id"]
            isOneToOne: false
            referencedRelation: "course_structure"
            referencedColumns: ["content_id"]
          },
        ]
      }
      course_catalog: {
        Row: {
          completed_contents: number | null
          course_description: string | null
          course_id: string | null
          course_title: string | null
          thumbnail_url: string | null
          total_contents: number | null
          total_modules: number | null
        }
        Relationships: []
      }
      course_structure: {
        Row: {
          content_duration: number | null
          content_id: string | null
          content_order: number | null
          content_title: string | null
          content_type: string | null
          course_id: string | null
          course_title: string | null
          is_completed: boolean | null
          module_id: string | null
          module_order: number | null
          module_title: string | null
        }
        Relationships: []
      }
      group_ranking_view: {
        Row: {
          avatar_url: string | null
          group_id: string | null
          rank_position: number | null
          total_points: number | null
          user_id: string | null
          user_name: string | null
        }
        Relationships: [
          {
            foreignKeyName: "user_points_group_id_fkey"
            columns: ["group_id"]
            isOneToOne: false
            referencedRelation: "permission_groups"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Functions: {
      fn_check_badges: {
        Args: { p_group_id: string; p_user_id: string }
        Returns: undefined
      }
      fn_update_streak: { Args: { p_user_id: string }; Returns: undefined }
      has_role: { Args: { required_roles: string[] }; Returns: boolean }
      search_content_fulltext: {
        Args: { filter_course_id?: string; search_query: string }
        Returns: {
          chunk_id: string
          chunk_text: string
          content_id: string
          content_title: string
          course_title: string
          module_title: string
          start_time: number
          thumbnail_url: string
        }[]
      }
      search_content_semantic: {
        Args: {
          filter_course_id?: string
          match_count?: number
          query_embedding: string
        }
        Returns: {
          chunk_id: string
          chunk_text: string
          content_id: string
          content_title: string
          course_title: string
          distance: number
          module_title: string
          start_time: number
          thumbnail_url: string
        }[]
      }
      search_transcripts: {
        Args: {
          course_filter?: string
          match_count?: number
          min_similarity?: number
          query_embedding: string
        }
        Returns: {
          chunk_id: string
          chunk_text: string
          content_id: string
          content_title: string
          course_id: string
          course_title: string
          end_time: number
          module_id: string
          similarity: number
          start_time: number
        }[]
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
