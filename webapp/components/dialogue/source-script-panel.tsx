"use client";

import type { Components } from "react-markdown";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import { Button } from "@/components/ui/button";
import { Textarea } from "@/components/ui/textarea";
import { cn } from "@/lib/utils";

const markdownComponents: Components = {
  h1: ({ children }) => (
    <h1 className="mb-3 mt-6 text-xl font-semibold tracking-tight first:mt-0">
      {children}
    </h1>
  ),
  h2: ({ children }) => (
    <h2 className="mb-2 mt-5 text-lg font-semibold tracking-tight first:mt-0">
      {children}
    </h2>
  ),
  h3: ({ children }) => (
    <h3 className="mb-2 mt-4 text-base font-semibold first:mt-0">{children}</h3>
  ),
  p: ({ children }) => (
    <p className="mb-3 leading-relaxed text-foreground/90 last:mb-0">
      {children}
    </p>
  ),
  strong: ({ children }) => (
    <strong className="font-semibold text-foreground">{children}</strong>
  ),
  em: ({ children }) => <em className="italic">{children}</em>,
  ul: ({ children }) => (
    <ul className="mb-3 list-disc space-y-1 pl-5 last:mb-0">{children}</ul>
  ),
  ol: ({ children }) => (
    <ol className="mb-3 list-decimal space-y-1 pl-5 last:mb-0">{children}</ol>
  ),
  li: ({ children }) => <li className="leading-relaxed">{children}</li>,
  hr: () => <hr className="my-5 border-border" />,
  blockquote: ({ children }) => (
    <blockquote className="mb-3 border-l-2 border-border pl-3 text-muted-foreground italic last:mb-0">
      {children}
    </blockquote>
  ),
  code: ({ className, children, ...props }) => {
    // Fenced blocks land as <pre><code className="language-…">; leave
    // background/padding to <pre> so we don't double-wrap.
    if (className) {
      return (
        <code className={cn("font-mono text-xs", className)} {...props}>
          {children}
        </code>
      );
    }
    return (
      <code
        className="rounded bg-muted px-1 py-0.5 font-mono text-[0.85em]"
        {...props}
      >
        {children}
      </code>
    );
  },
  pre: ({ children }) => (
    <pre className="mb-3 overflow-x-auto rounded-md bg-muted px-3 py-2 last:mb-0">
      {children}
    </pre>
  ),
  a: ({ href, children }) => (
    <a
      href={href}
      className="text-foreground underline underline-offset-2"
      target="_blank"
      rel="noreferrer"
    >
      {children}
    </a>
  ),
  table: ({ children }) => (
    <div className="mb-4 overflow-x-auto last:mb-0">
      <table className="w-full min-w-[28rem] border-collapse text-left text-sm">
        {children}
      </table>
    </div>
  ),
  thead: ({ children }) => (
    <thead className="border-b border-border bg-muted/60">{children}</thead>
  ),
  tbody: ({ children }) => (
    <tbody className="divide-y divide-border">{children}</tbody>
  ),
  tr: ({ children }) => <tr className="align-top">{children}</tr>,
  th: ({ children }) => (
    <th className="px-2.5 py-2 font-medium whitespace-nowrap text-foreground">
      {children}
    </th>
  ),
  td: ({ children }) => (
    <td className="px-2.5 py-2 text-foreground/90">{children}</td>
  ),
};

type SourceScriptPanelProps = {
  value: string;
  onChange: (value: string) => void;
  onCopy: () => void;
  onSave: () => void;
  isSaving: boolean;
};

export function SourceScriptPanel({
  value,
  onChange,
  onCopy,
  onSave,
  isSaving,
}: SourceScriptPanelProps) {
  const isEmpty = !value.trim();

  return (
    <div className="flex flex-col gap-3">
      <div className="grid min-h-[28rem] grid-cols-1 gap-3 lg:grid-cols-2 lg:gap-4">
        <section
          aria-labelledby="source-script-edit-label"
          className="flex min-h-[16rem] flex-col gap-2"
        >
          <h2
            id="source-script-edit-label"
            className="text-xs font-medium tracking-wide text-muted-foreground uppercase"
          >
            Edit
          </h2>
          <Textarea
            id="source-script-editor"
            aria-label="Source script markdown"
            rows={24}
            value={value}
            onChange={(e) => onChange(e.target.value)}
            className="min-h-[16rem] flex-1 resize-y font-mono text-xs leading-relaxed lg:min-h-[32rem]"
            placeholder="Paste the Claude .md Hana used to populate this scene. Copy it back when you want revisions."
            spellCheck={false}
          />
        </section>

        <section
          aria-labelledby="source-script-preview-label"
          className="flex min-h-[16rem] flex-col gap-2"
        >
          <h2
            id="source-script-preview-label"
            className="text-xs font-medium tracking-wide text-muted-foreground uppercase"
          >
            Preview
          </h2>
          <div
            role="region"
            aria-label="Rendered source script preview"
            tabIndex={0}
            className={cn(
              "min-h-[16rem] flex-1 overflow-auto rounded-lg border border-input bg-transparent px-3 py-3 text-sm outline-none focus-visible:border-ring focus-visible:ring-3 focus-visible:ring-ring/50 lg:min-h-[32rem] dark:bg-input/30",
              isEmpty && "flex items-start",
            )}
          >
            {isEmpty ? (
              <p className="text-sm text-muted-foreground">
                Live preview appears here. Markdown tables (Speaker / Japanese /
                English / Delivery) render with GFM.
              </p>
            ) : (
              <div className="source-script-preview">
                <ReactMarkdown
                  remarkPlugins={[remarkGfm]}
                  components={markdownComponents}
                >
                  {value}
                </ReactMarkdown>
              </div>
            )}
          </div>
        </section>
      </div>

      {isEmpty && (
        <p className="text-sm text-muted-foreground">
          Paste the Claude `.md` Hana used to populate this scene. Copy it back
          when you want revisions.
        </p>
      )}

      <div className="flex gap-2">
        <Button
          variant="outline"
          size="sm"
          onClick={onCopy}
          disabled={!value}
        >
          Copy
        </Button>
        <Button size="sm" onClick={onSave} disabled={isSaving}>
          Save
        </Button>
      </div>
    </div>
  );
}
