'use client';

import { useEffect, useState } from 'react';
import { useTheme } from 'next-themes';
import { Moon, Sun } from 'lucide-react';
import { buttonVariants } from '@/components/ui/button';
import { cn } from '@/lib/utils';

// fumadocs-ui's own ThemeSwitch renders lucide icons with `fill="currentColor"`,
// which this project's lucide-react version doesn't handle - the icon comes
// out blank. Simple custom toggle instead, using lucide's normal
// stroke-based rendering.
export function ThemeToggle({ className }: { className?: string }) {
  const { resolvedTheme, setTheme } = useTheme();
  const [mounted, setMounted] = useState(false);

  useEffect(() => {
    // One-shot hydration guard: `resolvedTheme` is only known client-side,
    // so this avoids rendering the wrong icon before the client takes over.
    // eslint-disable-next-line react-hooks/set-state-in-effect
    setMounted(true);
  }, []);

  return (
    <button
      type="button"
      aria-label="Toggle theme"
      onClick={() => setTheme(resolvedTheme === 'dark' ? 'light' : 'dark')}
      className={cn(
        buttonVariants({ variant: 'ghost', size: 'icon' }),
        className,
      )}
    >
      {mounted && resolvedTheme === 'dark' ? (
        <Sun className="size-4" />
      ) : (
        <Moon className="size-4" />
      )}
    </button>
  );
}
