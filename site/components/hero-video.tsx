import { Play } from 'lucide-react';

// Structured as a video from day one - `videoSrc`/`posterSrc` are the only
// things that need filling in once a real demo recording exists, no
// layout rework. Until then this renders a styled placeholder in the
// exact frame the real video will occupy.
export function HeroVideo({
  videoSrc,
  posterSrc,
}: {
  videoSrc?: string;
  posterSrc?: string;
}) {
  const hasVideo = Boolean(videoSrc);

  return (
    <div className="relative mx-auto w-full max-w-5xl">
      <div
        aria-hidden
        className="absolute -inset-x-6 -top-10 h-40 rounded-full opacity-40 blur-3xl"
        style={{ background: '#174d77' }}
      />
      <div className="relative aspect-16/9 overflow-hidden rounded-t-2xl border border-border bg-card shadow-2xl">
        {hasVideo ? (
          <video
            className="size-full object-cover"
            src={videoSrc}
            poster={posterSrc}
            controls
            playsInline
          />
        ) : (
          <div className="flex size-full flex-col items-center justify-center gap-4 bg-gradient-to-b from-muted/40 to-background">
            <button
              type="button"
              disabled
              className="flex items-center gap-2 rounded-full bg-foreground/10 px-5 py-2.5 text-sm font-medium text-foreground/70 backdrop-blur"
            >
              <Play className="size-4 fill-current" />
              Play demo
            </button>
            <span className="text-xs text-muted-foreground">
              Demo video coming soon
            </span>
          </div>
        )}
      </div>
    </div>
  );
}
