export interface AddressLinkProps {
  address: string;
  /** Explorer URL for the address or transaction. */
  href: string;
  /** Visible name; the truncated address shows beside it. */
  label?: string;
  className?: string;
}

/** Truncate in the middle, as the brand book asks: 0x7a3f…c91e. */
export function truncateMiddle(value: string, head = 6, tail = 4): string {
  return value.length <= head + tail + 1 ? value : `${value.slice(0, head)}…${value.slice(-tail)}`;
}

/** An address or hash linking to the explorer, truncated in the middle with the full value for assistive tech. */
export function AddressLink({ address, href, label, className }: AddressLinkProps) {
  return (
    <a
      href={href}
      target="_blank"
      rel="noreferrer"
      title={address}
      aria-label={`${label ? `${label}, ` : ''}${address} (opens the explorer)`}
      className={`font-mono underline decoration-[var(--line-strong)] underline-offset-4 hover:decoration-[var(--reserve)] ${className ?? ''}`}
    >
      {label ? <span className="font-sans">{label} </span> : null}
      {truncateMiddle(address)}
    </a>
  );
}
