export type ThemeId = 'main-light-blue' | 'dark' | 'green-wellness' | 'purple-premium' | 'black-gold';

export interface ThemeOption {
  id: ThemeId;
  label: string;
  description: string;
}
