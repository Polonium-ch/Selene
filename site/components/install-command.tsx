'use client';

import { useState } from 'react';
import { Check, Copy } from 'lucide-react';
import { installCommand } from '@/lib/shared';

export function InstallCommand() {
  const [copied, setCopied] = useState(false);

  async function handleCopy() {
    await navigator.clipboard.writeText(installCommand);
    setCopied(true);
    setTimeout(() => setCopied(false), 1500);
  }

  return (
    <button
      type="button"
      onClick={handleCopy}
      className="group flex w-full max-w-xl items-center justify-between gap-3 rounded-lg border border-border bg-card px-4 py-3 text-left font-mono text-sm text-card-foreground transition-colors hover:border-primary/50"
    >
      <span className="overflow-x-auto whitespace-nowrap">
        <span className="text-muted-foreground select-none">$ </span>
        {installCommand}
      </span>
      {copied ? (
        <Check className="size-4 shrink-0 text-primary" />
      ) : (
        <Copy className="size-4 shrink-0 text-muted-foreground group-hover:text-foreground" />
      )}
    </button>
  );
}
