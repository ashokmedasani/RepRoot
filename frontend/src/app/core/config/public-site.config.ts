export type PublicBrand = 'reproot' | 'studio';

export const PUBLIC_SITE = {
  parentUrl: 'https://www.rep-root.com',
  studioUrl: 'https://studio.rep-root.com',
  studioPortalUrl: 'https://studio.rep-root.com/portal',
  parentSupportEmail: 'support@rep-root.com',
  studioSupportEmail: 'studio.support@rep-root.com'
} as const;

export function publicSupportEmail(brand: PublicBrand): string {
  const configured = window.APP_CONFIG?.supportEmail?.trim();
  return configured || (brand === 'studio' ? PUBLIC_SITE.studioSupportEmail : PUBLIC_SITE.parentSupportEmail);
}
