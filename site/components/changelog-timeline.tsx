'use client';

import { useMemo, useState } from 'react';
import Markdown from 'react-markdown';
import { Badge } from '@/components/ui/badge';
import { cn } from '@/lib/utils';
import type { ChangelogEntry } from '@/lib/changelog';

const CATEGORY_STYLES: Record<string, string> = {
  New: 'bg-emerald-500/10 text-emerald-400 border-emerald-500/20',
  Changed: 'bg-blue-500/10 text-blue-400 border-blue-500/20',
  Fixed: 'bg-amber-500/10 text-amber-400 border-amber-500/20',
};

function categoryStyle(name: string) {
  return (
    CATEGORY_STYLES[name] ?? 'bg-muted text-muted-foreground border-border'
  );
}

export function ChangelogTimeline({ entries }: { entries: ChangelogEntry[] }) {
  const allCategories = useMemo(() => {
    const seen = new Set<string>();
    for (const entry of entries) {
      for (const category of entry.categories) seen.add(category.name);
    }
    return Array.from(seen);
  }, [entries]);

  const [activeCategories, setActiveCategories] = useState<Set<string>>(
    new Set(allCategories),
  );

  function toggleCategory(name: string) {
    setActiveCategories((prev) => {
      const next = new Set(prev);
      if (next.has(name)) next.delete(name);
      else next.add(name);
      return next;
    });
  }

  const visibleEntries = entries
    .map((entry) => ({
      ...entry,
      categories: entry.categories.filter((category) =>
        activeCategories.has(category.name),
      ),
    }))
    .filter((entry) => entry.categories.length > 0);

  return (
    <div>
      <div className="mb-10 flex flex-wrap items-center gap-2">
        <span className="mr-1 text-xs font-medium text-muted-foreground">
          Filter:
        </span>
        {allCategories.map((name) => {
          const active = activeCategories.has(name);
          return (
            <button
              key={name}
              type="button"
              onClick={() => toggleCategory(name)}
              className={cn(
                'rounded-full border px-3 py-1 text-xs font-medium transition-colors',
                active
                  ? categoryStyle(name)
                  : 'border-border text-muted-foreground hover:text-foreground',
              )}
            >
              {name}
            </button>
          );
        })}
      </div>

      <div className="relative space-y-10 border-l border-border pl-8">
        {visibleEntries.map((entry) => (
          <article
            key={entry.version}
            id={`v${entry.version}`}
            className="relative"
          >
            <span className="absolute top-1.5 -left-[calc(2rem+4.5px)] size-2 rounded-full bg-primary" />

            <div className="mb-3 flex flex-wrap items-baseline gap-3">
              <a
                href={`#v${entry.version}`}
                className="font-mono text-lg font-semibold hover:underline"
              >
                v{entry.version}
              </a>
              {entry.date && (
                <span className="text-sm text-muted-foreground">
                  {entry.date}
                </span>
              )}
            </div>

            <div className="mb-4 flex flex-wrap gap-2">
              {entry.categories.map((category) => (
                <Badge
                  key={category.name}
                  variant="outline"
                  className={categoryStyle(category.name)}
                >
                  {category.name} · {category.items.length}
                </Badge>
              ))}
            </div>

            <div className="space-y-5 rounded-xl border border-border bg-card p-6">
              {entry.categories.map((category) => (
                <div key={category.name}>
                  <h3 className="mb-2 text-sm font-medium">{category.name}</h3>
                  <div className="prose-neutral dark:prose-invert prose max-w-none prose-sm prose-p:my-0 prose-ul:my-0">
                    <Markdown>
                      {category.items.map((item) => `- ${item}`).join('\n')}
                    </Markdown>
                  </div>
                </div>
              ))}
            </div>
          </article>
        ))}

        {visibleEntries.length === 0 && (
          <p className="text-sm text-muted-foreground">
            No entries match the selected filters.
          </p>
        )}
      </div>
    </div>
  );
}
