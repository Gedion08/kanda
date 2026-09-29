import type { ReactNode } from 'react';

/** A labelled page section; its heading names the region for assistive tech. */
export function Section({ id, title, children }: { id: string; title: string; children: ReactNode }) {
  return (
    <section aria-labelledby={id} className="flex flex-col gap-4">
      <h2 id={id} className="text-lg font-bold tracking-tight">
        {title}
      </h2>
      {children}
    </section>
  );
}

/** A number that links to the explorer call that produced it (L5 section 5). */
export function Evidence({ href, call, children }: { href: string; call: string; children: ReactNode }) {
  return (
    <a
      href={href}
      target="_blank"
      rel="noreferrer"
      title={`${call}: open on the explorer`}
      className="underline decoration-line-strong decoration-1 underline-offset-4 hover:decoration-reserve"
    >
      {children}
    </a>
  );
}

type Tone = 'settled' | 'caution' | 'danger' | 'neutral';

const toneClass: Record<Tone, string> = {
  settled: 'text-settled border-settled',
  caution: 'text-caution border-caution',
  danger: 'text-danger border-danger',
  neutral: 'text-ink-muted border-line-strong',
};

const toneMark: Record<Tone, string> = { settled: '✓', caution: '!', danger: '✕', neutral: '•' };

/** A status in words with a matching mark; colour is never the only signal. */
export function Pill({ tone, children }: { tone: Tone; children: ReactNode }) {
  return (
    <span
      className={`inline-flex items-center gap-1.5 rounded border px-2 py-0.5 text-xs font-bold ${toneClass[tone]}`}
    >
      <span aria-hidden="true">{toneMark[tone]}</span>
      {children}
    </span>
  );
}

/** A horizontally scrollable table wrapper, so wide tables never scroll the page. */
export function TableFrame({ children }: { children: ReactNode }) {
  return (
    <div className="overflow-x-auto rounded-lg border border-line bg-surface-raised">
      <table className="w-full min-w-[36rem] border-collapse text-sm [&_tbody_tr]:border-b [&_tbody_tr]:border-line [&_tbody_tr:last-child]:border-b-0">
        {children}
      </table>
    </div>
  );
}

export const th =
  'border-b border-line px-4 py-3 text-left text-xs font-bold tracking-[0.06em] text-ink-muted uppercase';
/** Row separators live on tbody rows (TableFrame), so every column lines up. */
export const td = 'px-4 py-3 align-top';
