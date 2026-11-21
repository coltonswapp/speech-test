CREATE INDEX IF NOT EXISTS clip_feedback_status_cursor_idx ON clip_feedback (status, created_at, id);
--> statement-breakpoint
CREATE INDEX IF NOT EXISTS clip_feedback_issue_cursor_idx ON clip_feedback (created_at, id) WHERE status IS NOT NULL;
