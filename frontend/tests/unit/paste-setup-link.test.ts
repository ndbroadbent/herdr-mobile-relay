import { fireEvent, render, screen } from '@testing-library/svelte';
import { afterEach, describe, expect, it, vi } from 'vitest';
import PasteSetupLink from '$components/PasteSetupLink.svelte';
import { relayStore } from '$lib/store';
import { directSetupLink, gatewayInvitationLink, otherLink } from '../support/setup-qr';

afterEach(() => {
  vi.restoreAllMocks();
});

async function paste(text: string) {
  render(PasteSetupLink);
  const input = screen.getByLabelText('Setup or invitation link');
  await fireEvent.input(input, { target: { value: text } });
  await fireEvent.submit(input.closest('form')!);
  return input as HTMLInputElement;
}

describe('paste setup link', () => {
  it('imports a pasted setup link the way a scanned one is imported, then clears the field', async () => {
    const importSetupLink = vi.spyOn(relayStore, 'importSetupLink').mockReturnValue(true);
    const input = await paste(`  ${directSetupLink}\n`);
    const { hash, protocol, host } = new URL(directSetupLink);
    expect(importSetupLink).toHaveBeenCalledExactlyOnceWith({ hash, protocol, host }, true, false);
    expect(input.value).toBe('');
    expect(screen.queryByRole('alert')).toBeNull();
  });

  it('imports a device invitation link', async () => {
    const importSetupLink = vi.spyOn(relayStore, 'importSetupLink').mockReturnValue(true);
    await paste(gatewayInvitationLink);
    expect(importSetupLink).toHaveBeenCalledOnce();
    expect(importSetupLink.mock.calls[0]?.[0]?.hash).toContain('invite=');
  });

  it('refuses a link that is not a setup link, without importing it', async () => {
    const importSetupLink = vi.spyOn(relayStore, 'importSetupLink');
    const input = await paste(otherLink);
    expect(importSetupLink).not.toHaveBeenCalled();
    expect(screen.getByRole('alert')).toHaveTextContent('This is not a Herdr setup or invitation link.');
    expect(input.value).toBe(otherLink);
  });

  it('refuses an expired invitation', async () => {
    const importSetupLink = vi.spyOn(relayStore, 'importSetupLink');
    await paste(gatewayInvitationLink.replace('invite_expires=4102444800000', 'invite_expires=1000'));
    expect(importSetupLink).not.toHaveBeenCalled();
    expect(screen.getByRole('alert')).toHaveTextContent('This invitation has expired.');
  });

  it('explains when the store cannot use the link', async () => {
    vi.spyOn(relayStore, 'importSetupLink').mockReturnValue(false);
    await paste(directSetupLink);
    expect(screen.getByRole('alert')).toHaveTextContent('This link could not be used.');
  });
});
