export interface ChangelogCategory {
  name: string;
  items: string[];
}

export interface ChangelogEntry {
  version: string;
  date: string | null;
  categories: ChangelogCategory[];
}

// Tailored to this repo's CHANGELOG.md convention specifically (see the
// file's own header comment): `## [version] - date` sections, each with
// `### Category` subsections of `- item` bullets. Not a general-purpose
// markdown parser - the intro paragraph above the first `##` heading (a
// maintainer-facing note, not for end users) is intentionally dropped by
// only ever looking at `##`/`###`/`-` lines.
export function parseChangelog(markdown: string): ChangelogEntry[] {
  const entries: ChangelogEntry[] = [];
  let current: ChangelogEntry | null = null;
  let currentCategory: ChangelogCategory | null = null;

  for (const line of markdown.split('\n')) {
    const versionMatch = line.match(/^##\s+\[([^\]]+)\](?:\s*-\s*(.+))?/);
    if (versionMatch) {
      current = {
        version: versionMatch[1],
        date: versionMatch[2]?.trim() ?? null,
        categories: [],
      };
      entries.push(current);
      currentCategory = null;
      continue;
    }

    const categoryMatch = line.match(/^###\s+(.+)/);
    if (categoryMatch && current) {
      currentCategory = { name: categoryMatch[1].trim(), items: [] };
      current.categories.push(currentCategory);
      continue;
    }

    const itemMatch = line.match(/^-\s+(.+)/);
    if (itemMatch && currentCategory) {
      currentCategory.items.push(itemMatch[1].trim());
    }
  }

  // Drop version headings with no categories under them yet (e.g. an
  // empty `## [Unreleased]` between releases).
  return entries.filter((entry) => entry.categories.length > 0);
}
