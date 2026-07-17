import {
  MonitorSmartphone,
  Radar,
  Gamepad2,
  SlidersHorizontal,
} from 'lucide-react';
import { Badge } from '@/components/ui/badge';
import { buttonVariants } from '@/components/ui/button';
import {
  Accordion,
  AccordionItem,
  AccordionTrigger,
  AccordionContent,
} from '@/components/ui/accordion';
import { HeroVideo } from '@/components/hero-video';
import { InstallCommand } from '@/components/install-command';
import { ExternalLink } from '@/components/external-link';
import { GitHubIcon } from '@/components/icons';
import { gitConfig } from '@/lib/shared';

const features = [
  {
    icon: MonitorSmartphone,
    title: 'Streaming',
    description:
      'Hardware H.264 decoding (VideoToolbox) and native Opus audio (AudioToolbox) with stereo, 5.1, and 7.1 output. Session background/resume support and a blurred box-art backdrop while connecting.',
  },
  {
    icon: Radar,
    title: 'Discovery & Pairing',
    description:
      'Bonjour (mDNS) host discovery on the LAN, manual host entry for VPN/WAN setups, and NVIDIA GameStream / Sunshine PIN pairing.',
  },
  {
    icon: Gamepad2,
    title: 'Input',
    description:
      'Keyboard & mouse forwarding, plus gamepad support for any controller macOS pairs natively (DualSense, DualShock 4, Xbox, and other MFi/HID pads) — buttons, sticks, and analog triggers.',
  },
  {
    icon: SlidersHorizontal,
    title: 'Settings & Personalization',
    description:
      'A native Settings window (resolution, frame rate, bitrate, audio channels, HTTPS port, packet size), a native About window, and in-app auto-updates via Sparkle.',
  },
];

const faqs = [
  {
    question: 'Is Selene free?',
    answer:
      'Yes. Selene is free and open source under the GNU GPLv3 — the same license Moonlight uses.',
  },
  {
    question: 'How is this different from Moonlight?',
    answer:
      "Selene started as a fork of moonlight-qt, but has since become a complete native rewrite focused exclusively on macOS. The UI is built entirely in SwiftUI/AppKit, not Qt — the underlying GameStream protocol engine (moonlight-common-c) is still reused where it makes sense, since it's already proven and dependency-light.",
  },
  {
    question: 'Why Apple Silicon only?',
    answer:
      "A deliberate decision, not a limitation we plan to lift. Apple has been deprecating Intel Macs for years, and there's no Intel hardware available for testing — any Intel compatibility claim would be unreliable.",
  },
  {
    question: "It's not notarized — is it safe to install?",
    answer:
      "Selene isn't notarized by Apple (no paid Developer ID behind the project yet), so macOS will flag it as coming from an unidentified developer. The install script and manual steps both account for this by clearing the quarantine flag. Since it's fully open source, you're also free to audit the code or build it from source yourself.",
  },
  {
    question: 'Does it need a cloud account?',
    answer:
      'No. Selene talks directly to your Sunshine or NVIDIA GameStream host over your LAN (or a manually-entered address for VPN/WAN setups) — no cloud account, no relay server in the middle.',
  },
  {
    question: "What's next?",
    answer:
      'HEVC and AV1 decoding, codec capability negotiation, HDR / YUV 4:4:4, a performance overlay, and gamepad rumble/touchpad/motion/battery reporting are all on the roadmap.',
  },
];

export default function HomePage() {
  return (
    <main className="flex flex-1 flex-col">
      <section className="flex flex-col items-center gap-6 px-6 pt-20 pb-16 text-center">
        <Badge variant="outline">Apple Silicon only</Badge>

        <h1 className="max-w-4xl text-5xl leading-[1.05] font-bold tracking-tight sm:text-6xl">
          Native macOS streaming{' '}
          <span className="text-muted-foreground">
            for Sunshine &amp; NVIDIA GameStream.
          </span>
        </h1>

        <p className="max-w-xl text-base text-muted-foreground">
          Built with SwiftUI and Apple&apos;s native frameworks — a complete
          rewrite of the Moonlight/Sunshine client, focused exclusively on
          macOS.
        </p>

        <div className="flex flex-wrap items-center justify-center gap-3 pt-2">
          <ExternalLink
            href={`https://github.com/${gitConfig.user}/${gitConfig.repo}/releases/latest`}
            className={buttonVariants({ size: 'lg' })}
          >
            Download for macOS
          </ExternalLink>
          <ExternalLink
            href={`https://github.com/${gitConfig.user}/${gitConfig.repo}`}
            className={buttonVariants({ variant: 'outline', size: 'lg' })}
          >
            <GitHubIcon />
            View on GitHub
          </ExternalLink>
        </div>

        <div className="flex flex-wrap items-center justify-center gap-x-3 gap-y-1 pt-1 font-mono text-xs text-muted-foreground">
          <span>Free &amp; open source (GPLv3)</span>
          <span aria-hidden>·</span>
          <span>Apple Silicon native</span>
          <span aria-hidden>·</span>
          <span>No cloud — direct to your LAN</span>
        </div>

        <InstallCommand />
      </section>

      <section className="px-6 pb-24">
        <HeroVideo />
      </section>

      <section id="features" className="mx-auto w-full max-w-5xl px-6 pb-24">
        <div className="mx-auto mb-10 max-w-2xl text-center">
          <h2 className="text-2xl font-semibold tracking-tight sm:text-3xl">
            Everything you need to stream from a Sunshine host
          </h2>
          <p className="mt-2 text-sm text-muted-foreground">
            Full end-to-end streaming — video, audio, input, pairing, and
            session management — against real Sunshine hosts today.
          </p>
        </div>
        <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
          {features.map((feature) => (
            <div
              key={feature.title}
              className="rounded-xl border border-border bg-card p-6 transition-colors hover:border-primary/40"
            >
              <div className="mb-4 flex size-10 items-center justify-center rounded-lg border border-border bg-accent">
                <feature.icon className="size-5 text-foreground" />
              </div>
              <h3 className="mb-1.5 font-medium">{feature.title}</h3>
              <p className="text-sm text-muted-foreground">
                {feature.description}
              </p>
            </div>
          ))}
        </div>
      </section>

      <section className="mx-auto w-full max-w-3xl px-6 pb-28">
        <h2 className="mb-8 text-2xl font-semibold tracking-tight sm:text-3xl">
          Frequently asked questions
        </h2>
        <Accordion multiple={false}>
          {faqs.map((faq) => (
            <AccordionItem key={faq.question} value={faq.question}>
              <AccordionTrigger>{faq.question}</AccordionTrigger>
              <AccordionContent>{faq.answer}</AccordionContent>
            </AccordionItem>
          ))}
        </Accordion>
      </section>
    </main>
  );
}
