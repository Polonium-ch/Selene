import Link from 'next/link';
import { ExternalLink } from '@/components/external-link';
import { CopyrightYear } from '@/components/copyright-year';
import { GitHubIcon, SeleneIcon } from '@/components/icons';
import { appName, tagline, gitConfig } from '@/lib/shared';

const columns = [
  {
    title: 'Product',
    links: [
      { text: 'Features', href: '/#features' },
      { text: 'Changelog', href: '/changelog' },
      { text: 'Docs', href: '/docs' },
    ],
  },
  {
    title: 'Resources',
    links: [
      {
        text: 'Source code',
        href: `https://github.com/${gitConfig.user}/${gitConfig.repo}`,
      },
      {
        text: 'Releases',
        href: `https://github.com/${gitConfig.user}/${gitConfig.repo}/releases`,
      },
      {
        text: 'Building from source',
        href: `https://github.com/${gitConfig.user}/${gitConfig.repo}#-building`,
      },
    ],
  },
  {
    title: 'Legal',
    links: [
      { text: 'GPLv3 License', href: '/license' },
      {
        text: 'Security',
        href: `https://github.com/${gitConfig.user}/${gitConfig.repo}/blob/main/SECURITY.md`,
      },
    ],
  },
];

const MOONLIGHT_QT_URL = 'https://github.com/moonlight-stream/moonlight-qt';
const POLONIUM_URL = 'https://www.polonium.ch/';

export function SiteFooter() {
  return (
    <footer className="border-t border-border">
      <div className="mx-auto max-w-6xl px-6 py-14">
        <div className="grid grid-cols-2 gap-10 sm:grid-cols-5">
          <div className="col-span-2">
            <Link href="/" className="flex items-center gap-2">
              <span className="flex size-6 items-center justify-center rounded-md bg-primary text-primary-foreground">
                <SeleneIcon className="size-3.5" />
              </span>
              <span className="font-semibold tracking-tight">{appName}</span>
            </Link>
            <p className="mt-3 max-w-xs text-sm text-muted-foreground">
              {tagline}
            </p>
            <ExternalLink
              href={`https://github.com/${gitConfig.user}/${gitConfig.repo}`}
              className="mt-4 inline-flex items-center gap-2 text-sm text-muted-foreground transition-colors hover:text-foreground"
            >
              <GitHubIcon />
              {gitConfig.user}/{gitConfig.repo}
            </ExternalLink>
          </div>

          {columns.map((column) => (
            <div key={column.title}>
              <h3 className="text-sm font-medium">{column.title}</h3>
              <ul className="mt-3 space-y-2">
                {column.links.map((link) => {
                  const LinkComponent = link.href.startsWith('http')
                    ? ExternalLink
                    : Link;
                  return (
                    <li key={link.href}>
                      <LinkComponent
                        href={link.href}
                        className="text-sm text-muted-foreground transition-colors hover:text-foreground"
                      >
                        {link.text}
                      </LinkComponent>
                    </li>
                  );
                })}
              </ul>
            </div>
          ))}
        </div>

        <div className="mt-12 flex flex-col gap-2 border-t border-border pt-6 text-xs text-muted-foreground sm:flex-row sm:items-center sm:justify-between">
          <p>
            &copy; <CopyrightYear />{' '}
            <ExternalLink href={POLONIUM_URL} className="hover:text-foreground">
              Polonium
            </ExternalLink>
            . Licensed under the{' '}
            <Link href="/license" className="hover:text-foreground">
              GNU GPLv3
            </Link>
            .
          </p>
          <p>
            Originally forked from{' '}
            <ExternalLink
              href={MOONLIGHT_QT_URL}
              className="hover:text-foreground"
            >
              moonlight-qt
            </ExternalLink>
            .
          </p>
        </div>
      </div>
    </footer>
  );
}
