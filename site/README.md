# Selene site

Placeholder for getselene.ch (Next.js, deployed on Vercel) - kept in this repo instead of a
separate one since the only thing it actually shares with the app is
[`CHANGELOG.md`](../CHANGELOG.md), which it's meant to render as a changelog page.

## Vercel project setup

Once this is a real Next.js app:

- **Root Directory**: `site`
- **Ignored Build Step**: `bash scripts/vercel-ignore-build.sh`
  ([`vercel-ignore-build.sh`](scripts/vercel-ignore-build.sh)) - Vercel only watches
  the Root Directory by default, which would miss changes to `CHANGELOG.md` since it
  lives one level up.

## CI

`.github/workflows/build.yml` (the native macOS app build) ignores `site/**` and
`**.md` via `paths-ignore`, so changes here don't trigger an Xcode build.
