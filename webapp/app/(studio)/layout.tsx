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
          <div className="mx-auto flex h-14 max-w-7xl items-center justify-between px-6">
            <Link href="/content/dialogues" className="text-sm font-semibold tracking-tight">
              Shizen Studio
            </Link>
            <div className="flex items-center gap-4">
              <StudioNav />
              <div className="flex items-center gap-3 border-l border-border/60 pl-4">
                <NewDesignToggle />
                <ThemeToggle />
              </div>
            </div>
          </div>
        </header>
        <main className="mx-auto flex w-full max-w-7xl flex-1 flex-col px-6 py-8">
          {children}
        </main>
        <Toaster />
      </div>
    </QueryProvider>
  );
}
