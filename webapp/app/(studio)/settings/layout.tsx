import { SettingsSubnav } from "@/components/settings/settings-subnav";

export default function SettingsLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <div className="flex flex-1 flex-col gap-6">
      <div className="flex flex-col gap-4">
        <div>
          <h1 className="text-2xl font-semibold tracking-tight">Settings</h1>
          <p className="text-sm text-muted-foreground">
            Studio configuration — provider keys and Gemini TTS voice casting.
          </p>
        </div>
        <SettingsSubnav />
      </div>
      {children}
    </div>
  );
}
