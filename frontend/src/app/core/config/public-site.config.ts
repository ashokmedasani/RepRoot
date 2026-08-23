export type PublicBrand = 'reproot';

export const PUBLIC_SITE = {
  rootUrl: 'https://rep-root.com',
  portalUrl: 'https://rep-root.com/portal',
  supportEmail: 'support@rep-root.com'
} as const;

export function publicSupportEmail(_brand: PublicBrand): string {
  const configured = window.APP_CONFIG?.supportEmail?.trim();
  return configured || PUBLIC_SITE.supportEmail;
}
