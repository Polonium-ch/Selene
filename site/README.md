# Selene site

getselene.ch - the marketing site for [Selene](../README.md), a native macOS client for
Sunshine & NVIDIA GameStream. Built with Next.js + [Fumadocs](https://fumadocs.dev) +
[shadcn/ui](https://ui.shadcn.com).

Kept in the app's monorepo instead of a separate repo since the only thing it shares with
the app is [`CHANGELOG.md`](../CHANGELOG.md), which it renders as a changelog page.

Run development server:

```bash
pnpm dev
```

Open http://localhost:3000 with your browser to see the result.

## Explore

- `lib/source.ts`: Code for content source adapter, [`loader()`](https://fumadocs.dev/docs/headless/source-api) provides the interface to access your content.
- `lib/layout.shared.tsx`: Shared options for layouts, optional but preferred to keep.

| Route                     | Description                                                        |
| ------------------------- | ------------------------------------------------------------------ |
| `app/(home)`              | Landing page (hero, features, install CTA) and the changelog page. |
| `app/docs`                | Documentation layout and pages (empty for now).                    |
| `app/api/search/route.ts` | The Route Handler for search.                                      |

### Fumadocs MDX

A `source.config.ts` config file has been included, you can customise different options like frontmatter schema.

Read the [Introduction](https://fumadocs.dev/docs/mdx) for further details.

## Vercel project setup

- **Root Directory**: `site`
- **Ignored Build Step**: `bash scripts/vercel-ignore-build.sh`
  ([`vercel-ignore-build.sh`](scripts/vercel-ignore-build.sh)) - Vercel only watches
  the Root Directory by default, which would miss changes to `CHANGELOG.md` since it
  lives one level up.

## CI

`.github/workflows/build.yml` (the native macOS app build) ignores `site/**` and
`**.md` via `paths-ignore`, so changes here don't trigger an Xcode build.
