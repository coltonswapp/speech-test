import Link from "next/link";
import { Toaster } from "@/components/ui/sonner";
import { StudioNav } from "@/components/studio-nav";
import { QueryProvider } from "@/components/query-provider";
import { ThemeToggle } from "@/components/theme-toggle";
import { NewDesignToggle } from "@/components/new-design-toggle";

export default function StudioLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <QueryProvider>
      <div className="flex min-h-full flex-1 flex-col">
        <header className="sticky top-0 z-40 border-b border-border/60 bg-background/80 backdrop-blur">
          <div className="mx-auto flex h-14 max-w-7xl items-center gap-2 px-3 sm:gap-4 sm:px-6">
            <Link
              href="/content/dialogues"
              className="shrink-0 text-sm font-semibold tracking-tight"
            >
              Shizen Studio
            </Link>
            <StudioNav />
            <div className="flex shrink-0 items-center gap-3 border-l border-border/60 pl-4">
              <NewDesignToggle />
              <ThemeToggle />
              <Link
                href="/api/logout"
                className="text-xs text-muted-foreground hover:text-foreground"
              >
                Sign out
              </Link>
            </div>
          </div>
        </header>
        <main className="mx-auto flex w-full min-w-0 max-w-7xl flex-1 flex-col px-3 py-4 sm:px-6 sm:py-8">
          {children}
        </main>
        <Toaster />
      </div>
    </QueryProvider>
  );
}
