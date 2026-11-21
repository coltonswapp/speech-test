CREATE TABLE "studio_agent_token" (
	"id" text PRIMARY KEY NOT NULL,
	"name" text NOT NULL,
	"token_hash" text NOT NULL,
	"prefix" text NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"last_used_at" timestamp with time zone,
	"revoked_at" timestamp with time zone
);
--> statement-breakpoint
CREATE UNIQUE INDEX "studio_agent_token_hash_idx" ON "studio_agent_token" USING btree ("token_hash");
--> statement-breakpoint
CREATE UNIQUE INDEX "studio_agent_token_active_name_idx" ON "studio_agent_token" ("name") WHERE "revoked_at" IS NULL;
