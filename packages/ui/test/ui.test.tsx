// @vitest-environment jsdom
import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { AddressLink, MoneyText, truncateMiddle } from '../src/index.js';

describe('MoneyText', () => {
  it('shows 2 decimals and keeps full precision in the tooltip', () => {
    render(<MoneyText amount={999_123_456_789_000_000_000n} decimals={18} currency="KND" locale="en-US" />);
    const el = screen.getByText('999.12 KND');
    expect(el.getAttribute('title')).toBe('999.123456789 KND');
  });
});

describe('AddressLink', () => {
  it('truncates in the middle and opens the explorer in a new tab', () => {
    const address = '0x10E0caD60b43b1919238918CF00F06ebBfE118cf';
    render(
      <AddressLink address={address} href={`https://example.test/address/${address}`} label="KandaToken" />,
    );
    const link = screen.getByRole('link', {
      name: /KandaToken, 0x10E0caD60b43b1919238918CF00F06ebBfE118cf/u,
    });
    expect(link.textContent).toBe('KandaToken 0x10E0…18cf');
    expect(link.getAttribute('target')).toBe('_blank');
    expect(link.getAttribute('rel')).toBe('noreferrer');
  });

  it('leaves short values alone', () => {
    expect(truncateMiddle('0x1234')).toBe('0x1234');
  });
});
