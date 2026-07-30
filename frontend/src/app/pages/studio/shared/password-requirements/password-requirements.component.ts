import { Component, Input } from '@angular/core';

import { getPasswordRequirementStatus, PasswordRequirementStatus } from './password-requirements.util';

@Component({
  selector: 'app-password-requirements',
  standalone: true,
  templateUrl: './password-requirements.component.html',
  styleUrl: './password-requirements.component.scss'
})
export class PasswordRequirementsComponent {
  @Input() password = '';

  get requirements(): PasswordRequirementStatus[] {
    return getPasswordRequirementStatus(this.password);
  }
}
