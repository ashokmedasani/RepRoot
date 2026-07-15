import { Component, Input } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { IonIcon } from '@ionic/angular/standalone';
import { addIcons } from 'ionicons';
import { trashOutline } from 'ionicons/icons';

import { DynamicField } from '../core/api/forms-groups-api.service';

/** Shared Android editor for public-form and group-registration questions. */
@Component({
  selector: 'app-mobile-form-field-editor',
  standalone: true,
  imports: [FormsModule, IonIcon],
  template: `
    @for (field of fields; track $index) {
      <section class="field-card" [attr.aria-label]="'Form field ' + ($index + 1)">
        <div class="field-card__topline">
          <span>Field {{ $index + 1 }}</span>
          <button
            type="button"
            class="remove-field"
            [attr.aria-label]="'Remove ' + (field.label || 'field ' + ($index + 1))"
            (click)="removeField($index)"
          >
            <ion-icon name="trash-outline" aria-hidden="true" />
          </button>
        </div>

        <div class="field-card__grid">
          <label class="question-field">
            <span>Question</span>
            <textarea
              [(ngModel)]="field.label"
              [name]="'fieldLabel' + $index"
              placeholder="e.g. Primary Fitness Goal"
              rows="2"
            ></textarea>
          </label>

          <label>
            <span>Field type</span>
            <select [(ngModel)]="field.field_type" [name]="'fieldType' + $index">
              <option value="short_text">Short text</option>
              <option value="long_text">Long text</option>
              <option value="number">Number</option>
              <option value="phone">Phone</option>
              <option value="dropdown">Dropdown</option>
              <option value="yes_no">Yes / No</option>
              <option value="date">Date</option>
            </select>
          </label>
        </div>

        @if (field.field_type === 'dropdown') {
          <label class="options-field">
            <span>Options</span>
            <textarea
              [ngModel]="(field.options || []).join(', ')"
              (ngModelChange)="setOptions(field, $event)"
              [name]="'fieldOptions' + $index"
              placeholder="Weight Loss, Strength, Mobility"
              rows="2"
            ></textarea>
            <small>Separate each option with a comma.</small>
          </label>
        }

        <label class="required-field">
          <input type="checkbox" [(ngModel)]="field.required" [name]="'fieldRequired' + $index" />
          <span>Required field</span>
        </label>
      </section>
    }
  `,
  styles: [`
    :host { display: grid; gap: .8rem; margin-top: .8rem; min-width: 0; }
    .field-card { display: grid; gap: .75rem; min-width: 0; border: 1px solid var(--app-border); border-radius: var(--app-radius-lg); padding: .85rem; background: color-mix(in srgb, var(--app-surface) 96%, var(--app-primary-soft)); }
    .field-card__topline { display: flex; align-items: center; justify-content: space-between; gap: .75rem; }
    .field-card__topline > span { color: var(--app-primary-strong); font-size: .72rem; font-weight: 800; letter-spacing: .06em; text-transform: uppercase; }
    .remove-field { display: grid; width: 2.5rem; height: 2.5rem; flex: 0 0 2.5rem; place-items: center; border: 0; border-radius: var(--app-radius-sm); background: color-mix(in srgb, #dc2626 9%, var(--app-surface)); color: #dc2626; }
    .remove-field ion-icon { font-size: 1.1rem; }
    .field-card__grid { display: grid; grid-template-columns: minmax(0, 1fr); gap: .7rem; min-width: 0; }
    label { display: grid; gap: .35rem; min-width: 0; color: var(--app-text); }
    label > span { min-width: 0; color: var(--app-muted); font-size: .74rem; font-weight: 800; letter-spacing: .035em; line-height: 1.35; overflow-wrap: anywhere; text-transform: uppercase; }
    input:not([type='checkbox']), select, textarea { width: 100%; min-width: 0; min-height: 3rem; border: 1px solid var(--app-border); border-radius: var(--app-radius-md); outline: 0; padding: .7rem .8rem; background: var(--app-surface); color: var(--app-text); font: inherit; line-height: 1.4; }
    textarea { min-height: 4.1rem; resize: vertical; overflow-wrap: anywhere; }
    input:not([type='checkbox']):focus, select:focus, textarea:focus { border-color: var(--app-primary); box-shadow: var(--app-focus-ring); }
    .options-field small { color: var(--app-muted); font-size: .72rem; font-weight: 600; line-height: 1.4; overflow-wrap: anywhere; }
    .required-field { display: flex; min-height: 2.75rem; align-items: center; gap: .6rem; border-radius: var(--app-radius-sm); padding: .35rem .15rem; }
    .required-field input { width: 1.15rem; height: 1.15rem; flex: 0 0 1.15rem; margin: 0; accent-color: var(--app-primary); }
    .required-field span { color: var(--app-text); font-size: .84rem; letter-spacing: 0; text-transform: none; }
    @media (min-width: 520px) {
      .field-card__grid { grid-template-columns: minmax(0, 1.4fr) minmax(9.5rem, .6fr); }
    }
  `]
})
export class MobileFormFieldEditorComponent {
  @Input({ required: true }) fields: DynamicField[] = [];

  constructor() {
    addIcons({ trashOutline });
  }

  removeField(index: number): void {
    this.fields.splice(index, 1);
  }

  setOptions(field: DynamicField, raw: string): void {
    field.options = raw
      .split(',')
      .map((option) => option.trim())
      .filter(Boolean);
  }
}
