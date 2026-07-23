import 'zone.js';

import { provideHttpClient, withInterceptors } from '@angular/common/http';
import { ErrorHandler } from '@angular/core';
import { bootstrapApplication } from '@angular/platform-browser';
import { provideRouter, withInMemoryScrolling } from '@angular/router';

import { AppComponent } from './app/app.component';
import { routes } from './app/app.routes';
import { appErrorInterceptor } from './app/core/errors/error.interceptor';
import { GlobalAppErrorHandler } from './app/core/errors/global-error-handler';
import { platformHeaderInterceptor } from './app/core/errors/platform-header.interceptor';

bootstrapApplication(AppComponent, {
  providers: [
    provideHttpClient(withInterceptors([platformHeaderInterceptor, appErrorInterceptor])),
    { provide: ErrorHandler, useClass: GlobalAppErrorHandler },
    provideRouter(
      routes,
      withInMemoryScrolling({ scrollPositionRestoration: 'enabled', anchorScrolling: 'enabled' })
    )
  ]
}).catch((error: unknown) => console.error(error));
