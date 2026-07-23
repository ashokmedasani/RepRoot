import { HttpInterceptorFn } from '@angular/common/http';

/**
 * Tags every outgoing API request with its origin platform, so a backend
 * exception the client never sees (caught by admin_portal.middleware
 * .ErrorCaptureMiddleware) still lands in the right Admin Portal section.
 */
export const platformHeaderInterceptor: HttpInterceptorFn = (request, next) => {
  return next(request.clone({ setHeaders: { 'X-Client-Platform': 'web' } }));
};
