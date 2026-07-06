import { Component } from '@angular/core';
import { RouterLink } from '@angular/router';

type EntryMode = 'trainer' | 'client';

@Component({
  selector: 'app-access-entry-placeholder',
  standalone: true,
  imports: [RouterLink],
  templateUrl: './access-entry-placeholder.component.html',
  styleUrl: './access-entry-placeholder.component.scss'
})
export class AccessEntryPlaceholderComponent {
  selectedEntry: EntryMode | null = null;

  selectEntry(entry: EntryMode): void {
    this.selectedEntry = entry;
  }
}
