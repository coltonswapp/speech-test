import "server-only";

export type ProviderKey = "openai" | "elevenlabs" | "gemini";

const envVarByProvider: Record<ProviderKey, string> = {
  openai: "OPENAI_API_KEY",
  elevenlabs: "ELEVENLABS_API_KEY",
  gemini: "GEMINI_API_KEY",
};

export function getProviderKey(provider: ProviderKey): string {
  const value = process.env[envVarByProvider[provider]];
  return value?.trim() ?? "";
}

export function isProviderConfigured(provider: ProviderKey): boolean {
  return getProviderKey(provider).length > 0;
}

export function getProviderStatus(): Record<ProviderKey, boolean> {
  return {
    openai: isProviderConfigured("openai"),
    elevenlabs: isProviderConfigured("elevenlabs"),
    gemini: isProviderConfigured("gemini"),
  };
}

export function getAppPassphrase(): string {
  return process.env.APP_PASSPHRASE?.trim() ?? "";
}
