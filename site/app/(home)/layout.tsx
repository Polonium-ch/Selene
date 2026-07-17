import { SiteNav } from '@/components/site-nav';
import { SiteFooter } from '@/components/site-footer';

export default function Layout({ children }: LayoutProps<'/'>) {
  return (
    <div className="flex min-h-screen flex-col">
      <SiteNav />
      {children}
      <SiteFooter />
    </div>
  );
}
