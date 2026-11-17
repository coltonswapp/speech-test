"use client";

import { useState } from "react";
import { Loader2Icon, PencilIcon, TagsIcon } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select";
import { EditorSection } from "@/components/experiments/clips/editor-section";
import { cn } from "@/lib/utils";
import {
  CLIP_DIALECTS,
  CLIP_FORMATS,
  CLIP_PACE_FAST_FROM,
  CLIP_PACE_SLOW_BELOW,
  CLIP_REGISTERS,
  CLIP_SPEAKERS,
  CLIP_TOPICS,
  CLIP_TOPICS_MAX,
  clipEffectiveTags,
  clipPaceLabel,
  clipSpeechPace,
  clipTagLabel,
  type ClipTagPick,
  type ClipTagValues,
} from "@/lib/experiments/clips/tags";
import { clipIsAligned, type ClipDraft } from "@/lib/experiments/clips/types";

const EMPTY_PICK: ClipTagPick = {
  format: "other",
  topics: [],
  register: "casual",
  speakers: "monologue",
  dialect: "standard",
};

/** Stored tags as an editable pick; values no longer in the vocabulary fall back. */
function toPick(tags: ClipTagValues | null): ClipTagPick {
  if (!tags) return EMPTY_PICK;
  const pickOne = <T extends string>(list: readonly T[], value: string, fallback: T): T =>
    (list as readonly string[]).includes(value) ? (value as T) : fallback;
  return {
    format: pickOne(CLIP_FORMATS, tags.format, EMPTY_PICK.format),
    topics: tags.topics.filter((t): t is ClipTagPick["topics"][number] =>
      (CLIP_TOPICS as readonly string[]).includes(t)
    ),
    register: pickOne(CLIP_REGISTERS, tags.register, EMPTY_PICK.register),
    speakers: pickOne(CLIP_SPEAKERS, tags.speakers, EMPTY_PICK.speakers),
    dialect: pickOne(CLIP_DIALECTS, tags.dialect, EMPTY_PICK.dialect),
    ...(tags.series ? { series: tags.series } : {}),
  };
}

function FacetSelect<T extends string>({
  label,
  values,
  value,
  onChange,
  disabled,
}: {
  label: string;
  values: readonly T[];
  value: T;
  onChange: (value: T) => void;
  disabled: boolean;
}) {
  return (
    <label className="flex flex-col gap-1 text-xs text-muted-foreground">
      {label}
      <Select value={value} disabled={disabled} onValueChange={(v) => onChange(v as T)}>
        <SelectTrigger className="w-40" aria-label={label}>
          <SelectValue />
        </SelectTrigger>
        <SelectContent>
          {values.map((v) => (
            <SelectItem key={v} value={v}>
              {clipTagLabel(v)}
            </SelectItem>
          ))}
        </SelectContent>
      </Select>
    </label>
  );
}

/** Catalog tags: the Tag step's answer, or a hand-set one that wins. */
export function ClipTagsSection({
  draft,
  disabled,
  tagging,
  saving,
  onTag,
  onSave,
}: {
  draft: ClipDraft;
  disabled: boolean;
  tagging: boolean;
  saving: boolean;
  onTag: () => void;
  /** null = drop the hand-set tags (back to the Tag step's). */
  onSave: (pick: ClipTagPick | null) => Promise<unknown>;
}) {
  const tags = clipEffectiveTags(draft.tags);
  const auto = draft.tags?.auto;
  const manual = draft.tags?.manual;
  const pace = clipIsAligned(draft) ? clipSpeechPace(draft.sentences) : null;
  const [editing, setEditing] = useState<ClipTagPick | null>(null);

  const summary = tags
    ? [clipTagLabel(tags.format), ...tags.topics.map(clipTagLabel)].join(" · ").toLowerCase()
    : "not tagged";

  return (
    <EditorSection
      id="tags"
      title="7. Tags"
      summary={summary}
      actions={
        <>
          <Button
            size="sm"
            variant="ghost"
            disabled={disabled || editing !== null}
            onClick={() => setEditing(toPick(tags))}
          >
            <PencilIcon />
            Edit
          </Button>
          <Button
            size="sm"
            variant="outline"
            disabled={disabled || draft.sentences.length === 0}
            title={
              manual
                ? "Ask Gemini again; your hand-set tags still win"
                : "Tag format, topics, register, speakers and dialect from the title, channel and transcript"
            }
            onClick={onTag}
          >
            {tagging ? <Loader2Icon className="animate-spin" /> : <TagsIcon />}
            {auto ? "Re-tag" : "Tag"}
          </Button>
        </>
      }
    >
      {tags ? (
        <div className="flex flex-col gap-2">
          <div className="flex flex-wrap items-center gap-1.5">
            <Badge>{clipTagLabel(tags.format)}</Badge>
            {tags.topics.map((t) => (
              <Badge key={t} variant="secondary">
                {clipTagLabel(t)}
              </Badge>
            ))}
            <Badge variant="outline">{clipTagLabel(tags.register)}</Badge>
            <Badge variant="outline">{clipTagLabel(tags.speakers)}</Badge>
            <Badge variant="outline">{tags.dialect === "standard" ? "Standard Japanese" : clipTagLabel(tags.dialect)}</Badge>
            {tags.series ? <Badge variant="outline">{tags.series}</Badge> : null}
          </div>
          <p className="text-xs text-muted-foreground">
            {manual
              ? "Set by hand; the Tag step won’t overwrite it."
              : `Tagged by ${auto?.model ?? "Gemini"}${auto?.reason ? `: ${auto.reason}` : "."}`}
          </p>
          {auto?.suggested?.length ? (
            <p className="text-xs text-muted-foreground">
              Suggested values the vocabulary lacks: {auto.suggested.join(", ")}
            </p>
          ) : null}
        </div>
      ) : (
        <p className="text-xs text-muted-foreground">
          Not tagged yet, so the app leaves this clip out when it filters by format, topic or style.
        </p>
      )}

      <p className="text-xs text-muted-foreground">
        Pace:{" "}
        {pace !== null ? (
          <>
            <span className="font-medium text-foreground">{clipPaceLabel(pace)}</span>{" "}
            <span className="tabular-nums">({pace.toFixed(1)} characters/s)</span>. Measured from the
            timings: slow under {CLIP_PACE_SLOW_BELOW}, fast from {CLIP_PACE_FAST_FROM}.
          </>
        ) : (
          "measured once aligned."
        )}
      </p>

      {editing ? (
        <div className="flex flex-col gap-3 rounded-md border p-3">
          <div className="flex flex-wrap gap-3">
            <FacetSelect
              label="Format"
              values={CLIP_FORMATS}
              value={editing.format}
              disabled={saving}
              onChange={(format) => setEditing({ ...editing, format })}
            />
            <FacetSelect
              label="Register"
              values={CLIP_REGISTERS}
              value={editing.register}
              disabled={saving}
              onChange={(register) => setEditing({ ...editing, register })}
            />
            <FacetSelect
              label="Speakers"
              values={CLIP_SPEAKERS}
              value={editing.speakers}
              disabled={saving}
              onChange={(speakers) => setEditing({ ...editing, speakers })}
            />
            <FacetSelect
              label="Dialect"
              values={CLIP_DIALECTS}
              value={editing.dialect}
              disabled={saving}
              onChange={(dialect) => setEditing({ ...editing, dialect })}
            />
            <label className="flex flex-col gap-1 text-xs text-muted-foreground">
              Series
              <Input
                className="w-56"
                value={editing.series ?? ""}
                placeholder="e.g. 名探偵コナン"
                disabled={saving}
                onChange={(e) => {
                  const series = e.target.value;
                  setEditing({ ...editing, series: series.trim() ? series : undefined });
                }}
              />
            </label>
          </div>
          <div className="flex flex-col gap-1 text-xs text-muted-foreground">
            Topics (up to {CLIP_TOPICS_MAX}, most important first)
            <div className="flex flex-wrap gap-1.5">
              {CLIP_TOPICS.map((topic) => {
                const on = editing.topics.includes(topic);
                const full = !on && editing.topics.length >= CLIP_TOPICS_MAX;
                return (
                  <button
                    key={topic}
                    type="button"
                    disabled={saving || full}
                    className={cn(
                      "rounded-full border px-2 py-0.5 text-xs transition-colors",
                      on ? "border-primary bg-primary text-primary-foreground" : "hover:bg-muted",
                      full && "opacity-40"
                    )}
                    onClick={() =>
                      setEditing({
                        ...editing,
                        topics: on ? editing.topics.filter((t) => t !== topic) : [...editing.topics, topic],
                      })
                    }
                  >
                    {clipTagLabel(topic)}
                  </button>
                );
              })}
            </div>
          </div>
          <div className="flex flex-wrap gap-2">
            <Button
              size="sm"
              disabled={saving}
              onClick={async () => {
                const pick = { ...editing, ...(editing.series ? { series: editing.series.trim() } : {}) };
                await onSave(pick);
                setEditing(null);
              }}
            >
              {saving ? <Loader2Icon className="animate-spin" /> : null}
              Save tags
            </Button>
            {manual ? (
              <Button
                size="sm"
                variant="outline"
                disabled={saving}
                title={auto ? "Use the Tag step’s tags again" : "Clear the hand-set tags (the clip is untagged until Tag runs)"}
                onClick={async () => {
                  await onSave(null);
                  setEditing(null);
                }}
              >
                Back to automatic
              </Button>
            ) : null}
            <Button size="sm" variant="ghost" disabled={saving} onClick={() => setEditing(null)}>
              Cancel
            </Button>
          </div>
        </div>
      ) : null}
    </EditorSection>
  );
}
