import { Badge } from "@/components/ui/badge";
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card";
import { getProviderStatus, type ProviderKey } from "@/lib/secrets";

const providerLabels: Record<ProviderKey, string> = {
  openai: "OpenAI",
  elevenlabs: "ElevenLabs",
  gemini: "Gemini",
};

export default function SettingsKeysPage() {
  const status = getProviderStatus();
  const providers = Object.keys(providerLabels) as ProviderKey[];

  return (
    <Card>
      <CardHeader>
        <CardTitle className="text-base font-medium">Provider keys</CardTitle>
      </CardHeader>
      <CardContent className="flex flex-col gap-3">
        <p className="text-sm text-muted-foreground">
          API keys are configured via server environment variables, not entered
          here.
        </p>
        {providers.map((provider) => (
          <div
            key={provider}
            className="flex items-center justify-between rounded-md border border-border/60 px-4 py-3"
          >
            <span className="text-sm font-medium">
              {providerLabels[provider]}
            </span>
            <Badge variant={status[provider] ? "default" : "destructive"}>
              {status[provider] ? "Configured" : "Missing"}
            </Badge>
          </div>
        ))}
      </CardContent>
    </Card>
  );
}
