import { Component, Input, forwardRef } from '@angular/core';
import { ControlValueAccessor, NG_VALUE_ACCESSOR } from '@angular/forms';

@Component({
  selector: 'app-password-input',
  standalone: true,
  template: `
    <div class="password-field">
      <input
        [type]="isVisible ? 'text' : 'password'"
        [value]="value"
        [placeholder]="placeholder"
        [attr.autocomplete]="autocomplete"
        [required]="required"
        [disabled]="isDisabled"
        (input)="handleInput($event)"
        (blur)="onTouched()"
      />
      <button
        type="button"
        class="visibility-toggle"
        [attr.aria-label]="isVisible ? 'Hide password' : 'Show password'"
        [attr.aria-pressed]="isVisible"
        (click)="isVisible = !isVisible"
      >
        {{ isVisible ? 'Hide' : 'Show' }}
      </button>
    </div>
  `,
  styles: [`
    :host { display: block; }
    .password-field { position: relative; }
    input { width: 100%; min-height: 3rem; border: 1px solid var(--app-border); border-radius: var(--app-radius-md); outline: 0; padding: .7rem 3.8rem .7rem .8rem; background: var(--app-surface); color: var(--app-text); font: inherit; transition: border-color 160ms ease, box-shadow 160ms ease; }
    input:focus { border-color: var(--app-primary); box-shadow: var(--app-focus-ring); }
    .visibility-toggle { position: absolute; top: 50%; right: .4rem; min-width: 3rem; min-height: 2.1rem; border: 0; border-radius: var(--app-radius-sm); background: var(--app-primary-soft); color: var(--app-primary-strong); font: inherit; font-size: .72rem; font-weight: 800; transform: translateY(-50%); }
  `],
  providers: [{ provide: NG_VALUE_ACCESSOR, useExisting: forwardRef(() => PasswordInputComponent), multi: true }]
})
export class PasswordInputComponent implements ControlValueAccessor {
  @Input() placeholder = '';
  @Input() autocomplete = 'current-password';
  @Input() required = false;

  value = '';
  isVisible = false;
  isDisabled = false;

  private onChange: (value: string) => void = () => undefined;
  onTouched: () => void = () => undefined;

  writeValue(value: string | null): void {
    this.value = value || '';
  }

  registerOnChange(fn: (value: string) => void): void {
    this.onChange = fn;
  }

  registerOnTouched(fn: () => void): void {
    this.onTouched = fn;
  }

  setDisabledState(isDisabled: boolean): void {
    this.isDisabled = isDisabled;
  }

  handleInput(event: Event): void {
    this.value = (event.target as HTMLInputElement).value;
    this.onChange(this.value);
  }
}
