"""One place for how large an upload is allowed to be.

These limits were previously written inline at each validator -- 5 MB here,
10 MB there, 2 MB in the payment constants -- which meant the answer to "how
big can a photo be?" depended on which screen you were on, and tightening it
meant finding every literal.

Two numbers, deliberately:

* Images are capped at 1 MB. The web and Flutter clients downscale and
  re-encode a picture before uploading rather than refusing it, so this is a
  ceiling the user should never actually hit -- a phone photo comes through
  resized, not rejected. At the dimensions these images are displayed at
  (avatars, gallery tiles, a certificate preview) 1 MB is well past the point
  where more bytes stop being visible quality.

* PDFs are capped at 2 MB. There is no lossless way to shrink a PDF in the
  browser, so this one really is a refusal, and certificates and resource
  documents comfortably fit.

The server enforces both regardless of what any client does; the client-side
compression is a convenience, never the control.
"""

MEGABYTE = 1024 * 1024

#: Ceiling for anything that is an image, anywhere in the product.
IMAGE_MAX_BYTES = 1 * MEGABYTE

#: Ceiling for PDF documents (certificates, resource library files).
PDF_MAX_BYTES = 2 * MEGABYTE

IMAGE_MAX_LABEL = '1 MB'
PDF_MAX_LABEL = '2 MB'


def image_too_large_message(subject: str = 'Images') -> str:
  return (
    f'{subject} must be {IMAGE_MAX_LABEL} or smaller. '
    'Most photos are resized automatically before upload, so if you are seeing '
    'this, try saving the picture at a smaller size first.'
  )


def pdf_too_large_message(subject: str = 'PDF files') -> str:
  return f'{subject} must be {PDF_MAX_LABEL} or smaller.'
