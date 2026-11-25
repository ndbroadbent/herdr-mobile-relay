<script lang="ts">
  import Button from '$components/ui/Button.svelte';
  import { parseScannedSetupLink } from '$lib/setup-scan';
  import { relayStore } from '$lib/store';

  // An iPhone opens every link in Safari, never in the app saved to the Home Screen, which keeps
  // its own storage. Pasting the link imports it here exactly as scanning its QR code would.
  let { id = 'paste-setup-link', centered = false }: { id?: string; centered?: boolean } = $props();
  let link = $state('');
  let refusal = $state('');

  function submit(event: SubmitEvent) {
    event.preventDefault();
    const parsed = parseScannedSetupLink(link, location.protocol, Date.now());
    const result = typeof parsed === 'string' ? parsed : relayStore.importSetupLink(parsed, true, false);
    if (result === true) {
      link = '';
      refusal = '';
      return;
    }
    refusal = result === 'not-setup' ? 'This is not a Herdr setup or invitation link.'
      : result === 'expired' ? 'This invitation has expired. Create a new one and paste its link.'
        : 'This link could not be used. Print or create a new one and paste it.';
  }
</script>

<form class="paste-setup-link" class:centered onsubmit={submit}>
  <label class="field-label" for={id}>Setup or invitation link</label>
  <div class="paste-setup-row">
    <input
      {id}
      bind:value={link}
      oninput={() => { refusal = ''; }}
      type="url"
      required
      autocomplete="off"
      autocapitalize="off"
      spellcheck="false"
      placeholder="https://…#setup=…"
    />
    <Button type="submit" variant="secondary">Add</Button>
  </div>
  {#if refusal}<p class="hint paste-setup-refusal" role="alert">{refusal}</p>{/if}
</form>

<style>
  .paste-setup-link { display: grid; gap: .5rem; margin-block: 1rem 1.25rem; text-align: start; }
  .paste-setup-link.centered { width: min(100%, 24rem); margin-inline: auto; }
  .paste-setup-row { display: flex; gap: .5rem; }
  .paste-setup-row input { flex: 1; min-width: 0; }
  .paste-setup-refusal { margin: 0; color: var(--danger); }
</style>
