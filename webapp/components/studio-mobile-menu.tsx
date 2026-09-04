"use client";

import { useSyncExternalStore } from "react";
import { LogOutIcon, MoreHorizontalIcon } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuCheckboxItem,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { useDesignMode } from "@/components/design-mode-provider";

const noopSubscribe = () => () => {};

/**
 * Small-screen overflow for header controls that don't earn a permanent
 * spot next to the section picker: the New Design toggle and Sign out.
 */
export function StudioMobileMenu() {
  const { mode, setMode } = useDesignMode();
  // Hydrate as unchecked so SSR HTML matches; flip after mount.
  const mounted = useSyncExternalStore(
    noopSubscribe,
    () => true,
    () => false,
  );
  const newDesign = mounted && mode === "new";

  return (
    <DropdownMenu>
      <DropdownMenuTrigger
        render={
          <Button
            type="button"
            variant="ghost"
            size="icon"
            className="size-10 touch-manipulation"
            aria-label="More options"
          >
            <MoreHorizontalIcon className="size-4" />
          </Button>
        }
      />
      <DropdownMenuContent align="end" className="min-w-48 w-auto">
        <DropdownMenuLabel>Appearance</DropdownMenuLabel>
        <DropdownMenuCheckboxItem
          className="min-h-10 touch-manipulation"
          checked={newDesign}
          onCheckedChange={(next) => setMode(next ? "new" : "classic")}
          closeOnClick={false}
        >
          New Design
        </DropdownMenuCheckboxItem>
        <DropdownMenuSeparator />
        <DropdownMenuItem
          className="min-h-10 touch-manipulation"
          // Route handler that clears the cookie and redirects — needs a full
          // navigation, not a client-side transition.
          onClick={() => window.location.assign("/api/logout")}
        >
          <LogOutIcon className="size-4 text-muted-foreground" />
          Sign out
        </DropdownMenuItem>
      </DropdownMenuContent>
    </DropdownMenu>
  );
}
