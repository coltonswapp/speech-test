"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { CheckIcon, CopyIcon } from "lucide-react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";

export type AgentTokenListItem = {
  id: string;
  name: string;
  prefix: string;
  createdAt: string;
  lastUsedAt: string | null;
};

function formatWhen(iso: string | null): string {
  if (!iso) return "Never";
  const date = new Date(iso);
  if (!Number.isFinite(date.getTime())) return iso;
  return (
    new Intl.DateTimeFormat("en-US", {
      dateStyle: "medium",
      timeStyle: "short",
      timeZone: "UTC",
    }).format(date) + " UTC"
  );
}

export function AgentTokensPanel({
  tokens,
  loadError,
}: {
  tokens: AgentTokenListItem[];
  loadError: string | null;
}) {
  const router = useRouter();
  const [name, setName] = useState("");
  const [creating, setCreating] = useState(false);
  const [revokingId, setRevokingId] = useState<string | null>(null);
  const [plaintext, setPlaintext] = useState<{ name: string; token: string } | null>(null);
  const [copied, setCopied] = useState(false);

  async function createToken(event: React.FormEvent) {
    event.preventDefault();
    setCreating(true);
    setCopied(false);
    try {
      const res = await fetch("/api/settings/agent-tokens", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name }),
      });
      const body = (await res.json().catch(() => null)) as
        | { token?: string; tokenRecord?: { name: string }; error?: string }
        | null;
      if (!res.ok || !body?.token || !body.tokenRecord) {
        toast.error(body?.error ?? "Could not create token.");
        return;
      }
      setPlaintext({ name: body.tokenRecord.name, token: body.token });
      setName("");
      router.refresh();
    } catch {
      toast.error("Could not create token.");
    } finally {
      setCreating(false);
    }
  }

  async function revokeToken(item: AgentTokenListItem) {
    if (
      !confirm(
        `Revoke “${item.name}”? Bots using this token will fail until you issue a new one.`,
      )
    ) {
      return;
    }
    setRevokingId(item.id);
    try {
      const res = await fetch(`/api/settings/agent-tokens/${encodeURIComponent(item.id)}`, {
        method: "DELETE",
      });
      const body = (await res.json().catch(() => null)) as { error?: string } | null;
      if (!res.ok) {
        toast.error(body?.error ?? "Could not revoke token.");
        return;
      }
      toast.success(`Revoked ${item.name}.`);
      if (plaintext?.name === item.name) setPlaintext(null);
      router.refresh();
    } catch {
      toast.error("Could not revoke token.");
    } finally {
      setRevokingId(null);
    }
  }

  async function copyToken() {
    if (!plaintext) return;
    try {
      await navigator.clipboard.writeText(plaintext.token);
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch {
      toast.error("Couldn’t copy. Select the token and copy it instead.");
    }
  }

  return (
    <div className="flex flex-col gap-6">
      <Card>
        <CardHeader>
          <CardTitle className="text-base font-medium">Create a token</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col gap-4">
          <p className="text-sm text-muted-foreground">
            Issue one named token per bot (OpenBot, Kenji, Grok connector, Studio MCP).
            The shared <code className="font-mono text-xs">STUDIO_AGENT_TOKEN</code> env
            var still works during migration. Plaintext is shown once.
          </p>
          <form onSubmit={(event) => void createToken(event)} className="flex flex-col gap-3 sm:flex-row sm:items-end">
            <div className="flex min-w-0 flex-1 flex-col gap-1.5">
              <Label htmlFor="agent-token-name">Name</Label>
              <Input
                id="agent-token-name"
                value={name}
                onChange={(event) => setName(event.target.value)}
                placeholder="OpenBot"
                maxLength={80}
                required
                autoComplete="off"
              />
            </div>
            <Button type="submit" disabled={creating || !name.trim()}>
              {creating ? "Creating…" : "Create token"}
            </Button>
          </form>
          {plaintext ? (
            <div className="flex flex-col gap-2 rounded-lg border border-border/60 bg-muted/40 p-3">
              <p className="text-sm font-medium">
                Token for {plaintext.name} — copy it now. It won’t be shown again.
              </p>
              <div className="flex items-start gap-2">
                <code className="min-w-0 flex-1 rounded-lg border border-border/60 bg-background px-3 py-2 font-mono text-xs break-all select-all">
                  {plaintext.token}
                </code>
                <Button
                  type="button"
                  variant="outline"
                  size="icon"
                  aria-label="Copy token"
                  onClick={() => void copyToken()}
                >
                  {copied ? <CheckIcon /> : <CopyIcon />}
                </Button>
              </div>
            </div>
          ) : null}
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle className="text-base font-medium">Active tokens</CardTitle>
        </CardHeader>
        <CardContent className="flex flex-col gap-3">
          {loadError ? (
            <p className="text-sm text-destructive">{loadError}</p>
          ) : tokens.length === 0 ? (
            <p className="text-sm text-muted-foreground">
              No named tokens yet. Create one per agent so rotating a single token
              doesn’t lock the others out.
            </p>
          ) : (
            <div className="overflow-x-auto">
              <table className="w-full text-left text-sm">
                <thead>
                  <tr className="border-b border-border/60 text-muted-foreground">
                    <th className="py-2 pr-3 font-medium">Name</th>
                    <th className="py-2 pr-3 font-medium">Prefix</th>
                    <th className="py-2 pr-3 font-medium">Created</th>
                    <th className="py-2 pr-3 font-medium">Last used</th>
                    <th className="py-2 font-medium">
                      <span className="sr-only">Revoke</span>
                    </th>
                  </tr>
                </thead>
                <tbody>
                  {tokens.map((item) => (
                    <tr key={item.id} className="border-b border-border/40 last:border-0">
                      <td className="py-2.5 pr-3 font-medium">{item.name}</td>
                      <td className="py-2.5 pr-3 font-mono text-xs text-muted-foreground">
                        {item.prefix}…
                      </td>
                      <td className="py-2.5 pr-3 text-muted-foreground whitespace-nowrap">
                        {formatWhen(item.createdAt)}
                      </td>
                      <td className="py-2.5 pr-3 text-muted-foreground whitespace-nowrap">
                        {formatWhen(item.lastUsedAt)}
                      </td>
                      <td className="py-2.5 text-right">
                        <Button
                          type="button"
                          variant="destructive"
                          size="sm"
                          disabled={revokingId === item.id}
                          onClick={() => void revokeToken(item)}
                        >
                          {revokingId === item.id ? "Revoking…" : "Revoke"}
                        </Button>
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  );
}
