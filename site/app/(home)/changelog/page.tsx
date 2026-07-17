import fs from 'node:fs/promises';
import path from 'node:path';
import type { Metadata } from 'next';
import { buttonVariants } from '@/components/ui/button';
import { ExternalLink } from '@/components/external-link';
import { ChangelogTimeline } from '@/components/changelog-timeline';
import { parseChangelog } from '@/lib/changelog';
import { appName, gitConfig } from '@/lib/shared';

// CHANGELOG.md lives at the repo root, one level above the site's Root
// Directory - scripts/vercel-ignore-build.sh already watches it alongside
// site/ so Vercel rebuilds when it changes.
const CHANGELOG_PATH = path.join(process.cwd(), '..', 'CHANGELOG.md');

export const metadata: Metadata = {
  title: `Changelog — ${appName}`,
};

export default async function ChangelogPage() {
  const raw = await fs.readFile(CHANGELOG_PATH, 'utf-8');
  const entries = parseChangelog(raw);
  const latest = entries[0];

  return (
    <main className="mx-auto w-full max-w-3xl px-6 py-16">
      <p className="mb-3 text-xs font-medium tracking-wider text-muted-foreground uppercase">
        Changelog
      </p>
      <h1 className="text-4xl font-bold tracking-tight sm:text-5xl">
        Every release, documented.
      </h1>
      <p className="mt-3 max-w-xl text-muted-foreground">
        New features, changes, and fixes — pulled straight from the same file
        that feeds the in-app Sparkle updater.
      </p>

      {latest && (
        <div className="mt-8 flex flex-wrap items-center justify-between gap-4 rounded-xl border border-border bg-card p-6">
          <div>
            <p className="text-xs text-muted-foreground">Latest release</p>
            <p className="font-mono text-2xl font-semibold">
              v{latest.version}
              {latest.date && (
                <span className="ml-2 text-base font-normal text-muted-foreground">
                  {latest.date}
                </span>
              )}
            </p>
          </div>
          <div className="flex flex-wrap gap-2">
            <ExternalLink
              href={`https://github.com/${gitConfig.user}/${gitConfig.repo}/releases/tag/v${latest.version}`}
              className={buttonVariants({ variant: 'outline' })}
            >
              View release notes
            </ExternalLink>
            <ExternalLink
              href={`https://github.com/${gitConfig.user}/${gitConfig.repo}/releases/latest`}
              className={buttonVariants()}
            >
              Download
            </ExternalLink>
          </div>
        </div>
      )}

      <div className="mt-14">
        <ChangelogTimeline entries={entries} />
      </div>
    </main>
  );
}
