import Link from 'next/link';
import { ThemeToggle } from '@/components/theme-toggle';
import { ExternalLink } from '@/components/external-link';
import { buttonVariants } from '@/components/ui/button';
import { GitHubIcon, SeleneIcon } from '@/components/icons';
import { appName, gitConfig } from '@/lib/shared';

const links = [
  { text: 'Docs', href: '/docs' },
  { text: 'Changelog', href: '/changelog' },
];

export function SiteNav() {
  return (
    <header className="sticky top-0 z-50 border-b border-border/60 bg-background/80 backdrop-blur-md">
      <div className="mx-auto flex h-14 max-w-6xl items-center justify-between px-6">
        <Link href="/" className="flex items-center gap-2">
          <span className="flex size-6 items-center justify-center rounded-md bg-primary text-primary-foreground">
            <SeleneIcon className="size-3.5" />
          </span>
          <span className="font-semibold tracking-tight">{appName}</span>
        </Link>

        <nav className="hidden items-center gap-6 text-sm text-muted-foreground sm:flex">
          {links.map((link) => (
            <Link
              key={link.href}
              href={link.href}
              className="transition-colors hover:text-foreground"
            >
              {link.text}
            </Link>
          ))}
        </nav>

        <div className="flex items-center gap-2">
          <ThemeToggle />
          <ExternalLink
            href={`https://github.com/${gitConfig.user}/${gitConfig.repo}`}
            className={buttonVariants({ variant: 'ghost', size: 'icon' })}
            aria-label="GitHub"
          >
            <GitHubIcon />
          </ExternalLink>
          <ExternalLink
            href={`https://github.com/${gitConfig.user}/${gitConfig.repo}/releases/latest`}
            className={buttonVariants({ size: 'sm' })}
          >
            Install
          </ExternalLink>
        </div>
      </div>
    </header>
  );
}
