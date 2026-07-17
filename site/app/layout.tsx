import type { Metadata } from 'next';
import { RootProvider } from 'fumadocs-ui/provider/next';
import './global.css';
import { Inter, Geist } from 'next/font/google';
import { cn } from '@/lib/utils';
import { appName, tagline } from '@/lib/shared';

const geist = Geist({ subsets: ['latin'], variable: '--font-sans' });

const inter = Inter({
  subsets: ['latin'],
});

export const metadata: Metadata = {
  title: `${appName} — ${tagline}`,
  description: tagline,
};

export default function Layout({ children }: LayoutProps<'/'>) {
  return (
    <html
      lang="en"
      className={cn(inter.className, 'font-sans', geist.variable)}
      suppressHydrationWarning
    >
      <body className="flex min-h-screen flex-col">
        <RootProvider
          theme={{ defaultTheme: 'dark', disableTransitionOnChange: false }}
        >
          {children}
        </RootProvider>
      </body>
    </html>
  );
}
