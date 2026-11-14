import Link from "next/link";
import { ClapperboardIcon } from "lucide-react";

const experiments = [
  {
    href: "/experiments/clips",
    title: "Clip transcripts",
    description:
      "YouTube clip → ASR → tokens → word timestamps, for the word-synced clip player POC.",
    icon: ClapperboardIcon,
  },
];

export default function ExperimentsPage() {
  return (
    <div className="flex flex-col gap-6">
      <div>
        <h1 className="text-xl font-semibold tracking-tight">Experiments</h1>
        <p className="text-sm text-muted-foreground">
          Prototypes that aren’t part of the content pipeline yet.
        </p>
      </div>
      <div className="grid gap-3 sm:grid-cols-2 lg:grid-cols-3">
        {experiments.map(({ href, title, description, icon: Icon }) => (
          <Link
            key={href}
            href={href}
            className="flex flex-col gap-2 rounded-xl border border-border/60 p-4 transition-colors hover:bg-muted/50"
          >
            <div className="flex items-center gap-2 font-medium">
              <Icon className="size-4 text-muted-foreground" />
              {title}
            </div>
            <p className="text-sm text-muted-foreground">{description}</p>
          </Link>
        ))}
      </div>
    </div>
  );
}
