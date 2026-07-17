import Link from 'next/link';
import type { ComponentProps } from 'react';

// Thin wrapper so every external link consistently opens in a new tab -
// `rel="noopener noreferrer"` prevents the new tab from getting a handle
// back to this page via `window.opener`.
export function ExternalLink(props: ComponentProps<typeof Link>) {
  return <Link target="_blank" rel="noopener noreferrer" {...props} />;
}
