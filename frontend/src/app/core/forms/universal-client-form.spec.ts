import { describe, expect, it } from 'vitest';

import {
  buildUniversalClientFormFields,
  UNIVERSAL_CLIENT_FORM_FIELDS
} from './universal-client-form';

describe('buildUniversalClientFormFields', () => {
  it('returns an editable copy without changing the shared form template', () => {
    const fields = buildUniversalClientFormFields();

    expect(fields).toEqual(UNIVERSAL_CLIENT_FORM_FIELDS);
    expect(fields).not.toBe(UNIVERSAL_CLIENT_FORM_FIELDS);
    expect(fields[0].options).not.toBe(UNIVERSAL_CLIENT_FORM_FIELDS[0].options);

    fields[0].label = 'Changed label';
    fields[1].options?.push('Changed option');

    expect(UNIVERSAL_CLIENT_FORM_FIELDS[0].label).toBe('Phone Number');
    expect(UNIVERSAL_CLIENT_FORM_FIELDS[1].options).not.toContain('Changed option');
  });
});
