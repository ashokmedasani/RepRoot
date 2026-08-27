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

  /**
   * The rules stay hidden until the user starts typing.
   *
   * Shown up-front they are just a wall of red crosses next to an empty field --
   * a list of ways the user has already failed before touching anything. Once
   * they begin typing the same list becomes live feedback on progress, which is
   * the only moment it earns its space.
   */
  get isVisible(): boolean {
    return this.password.length > 0;
  }

  get requirements(): PasswordRequirementStatus[] {
    return getPasswordRequirementStatus(this.password);
  }
}
