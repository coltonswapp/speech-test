/**
 * Two-gate publish pipeline position for Review queue cards.
 * Derived from existing fields — no new schema.
 *
 * - Staged: take still has review work (flags) and/or is not the published take
 * - In database: this take is the scene's published variant (Gate A landed)
 * - Client-visible: parent lesson `isActive` (Gate B)
 */
export type PublishPipelineStage = "staged" | "in_database" | "client_visible";

export type PublishPipeline = {
  /** Stages reached (cumulative). */
  reached: {
    staged: boolean;
    inDatabase: boolean;
    clientVisible: boolean;
  };
  /** Furthest stage reached — useful for a single badge. */
  current: PublishPipelineStage;
};

export function derivePublishPipeline(params: {
  /** Still has auto-stamp flags / waiting in review. */
  hasFlags: boolean;
  isPublishedTake: boolean;
  /** Lesson Gate B — visible in the learner app. */
  collectionIsActive: boolean | null;
}): PublishPipeline {
  const inDatabase = params.isPublishedTake;
  // Lesson live without this take published still means Gate B is on for the
  // lesson; show client-visible only when this take has also landed in DB so
  // the pipeline reads left-to-right.
  const clientVisible = inDatabase && params.collectionIsActive === true;
  // Anything in the review queue is staged work; also true until Gate A lands.
  const staged = params.hasFlags || !inDatabase;

  let current: PublishPipelineStage = "staged";
  if (clientVisible) current = "client_visible";
  else if (inDatabase) current = "in_database";

  return {
    reached: {
      staged,
      inDatabase,
      clientVisible,
    },
    current,
  };
}
