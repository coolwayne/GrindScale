import liff from "@line/liff";

const LIFF_ID = (import.meta.env.VITE_LIFF_ID as string | undefined)?.trim() ?? "";

export interface LiffContext {
  enabled: boolean;
  inClient: boolean;
  displayName: string | null;
}

export async function initLiff(): Promise<LiffContext> {
  if (!LIFF_ID) {
    return { enabled: false, inClient: false, displayName: null };
  }
  await liff.init({ liffId: LIFF_ID });
  const inClient = liff.isInClient();
  let displayName: string | null = null;
  if (liff.isLoggedIn()) {
    try {
      const profile = await liff.getProfile();
      displayName = profile.displayName;
    } catch {
      displayName = null;
    }
  }
  return { enabled: true, inClient, displayName };
}

export function closeLiffWindow(): void {
  if (LIFF_ID && liff.isInClient()) {
    liff.closeWindow();
  }
}
