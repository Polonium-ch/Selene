import fs from 'node:fs/promises';
import path from 'node:path';
import type { Metadata } from 'next';
import { appName } from '@/lib/shared';

// LICENSE lives at the repo root, one level above the site's Root
// Directory - same pattern as the changelog page.
const LICENSE_PATH = path.join(process.cwd(), '..', 'LICENSE');

export const metadata: Metadata = {
  title: `License — ${appName}`,
};

export default async function LicensePage() {
  const license = await fs.readFile(LICENSE_PATH, 'utf-8');

  return (
    <main className="mx-auto w-full max-w-3xl px-6 py-16">
      <p className="mb-3 text-xs font-medium tracking-wider text-muted-foreground uppercase">
        License
      </p>
      <h1 className="text-4xl font-bold tracking-tight sm:text-5xl">
        GNU GPLv3
      </h1>
      <p className="mt-3 max-w-xl text-muted-foreground">
        {appName} is licensed under the GNU General Public License v3.0 — the
        same license Moonlight uses.
      </p>

      <pre className="mt-10 overflow-x-auto rounded-xl border border-border bg-card p-6 font-mono text-xs leading-relaxed whitespace-pre-wrap text-muted-foreground">
        {license}
      </pre>
    </main>
  );
}
