/**
 * Shrink a chosen image until it fits the product's 1 MB upload ceiling.
 *
 * Why compress rather than refuse: a photo straight off a phone is routinely
 * 3-8 MB, and none of those bytes survive being displayed as a 200px avatar or
 * a gallery tile. Rejecting the file makes the user go and find image-editing
 * software; resizing it here gets them the same visible result with no work.
 * The server still enforces the limit independently — this is a convenience,
 * never the control.
 *
 * The approach is deliberately boring: cap the longest edge, re-encode as
 * JPEG, and walk the quality down in steps until the result fits. Each step
 * re-encodes from the already-resized canvas, so it costs one draw and a few
 * cheap encodes rather than a full resize per attempt.
 */

/** Product-wide image ceiling. Mirrors IMAGE_MAX_BYTES in upload_limits.py. */
export const IMAGE_MAX_BYTES = 1024 * 1024;

/** Product-wide PDF ceiling. Mirrors PDF_MAX_BYTES in upload_limits.py. */
export const PDF_MAX_BYTES = 2 * 1024 * 1024;

/**
 * Aim slightly under the hard limit. Encoders are not perfectly predictable
 * and a file that lands at 1,048,570 bytes would pass here and fail on a
 * server that counts a multipart boundary differently.
 */
const TARGET_BYTES = Math.floor(IMAGE_MAX_BYTES * 0.92);

/**
 * Longest edge after resizing. Larger than anything the app displays (the
 * biggest is a full-width gallery image), so this is invisible in practice
 * while removing most of the weight of a modern phone photo.
 */
const MAX_EDGE_PX = 1600;

const QUALITY_STEPS = [0.85, 0.75, 0.65, 0.55, 0.45];

export interface CompressionResult {
  file: File;
  /** True when the image was re-encoded rather than passed through unchanged. */
  wasCompressed: boolean;
  originalBytes: number;
  finalBytes: number;
}

/** Formats a byte count the way the upload messages do. */
export function formatBytes(bytes: number): string {
  if (bytes >= 1024 * 1024) {
    return `${(bytes / (1024 * 1024)).toFixed(1)} MB`;
  }
  return `${Math.max(1, Math.round(bytes / 1024))} KB`;
}

/**
 * Returns a file guaranteed to be an image under the ceiling, or throws with a
 * message worth showing if it cannot get there.
 *
 * GIFs are passed through untouched when they already fit: drawing one to a
 * canvas keeps only the first frame, so silently turning an animation into a
 * still would be worse than leaving it alone.
 */
export async function compressImageFile(file: File): Promise<CompressionResult> {
  const unchanged = (reason?: string): CompressionResult => {
    if (file.size > IMAGE_MAX_BYTES) {
      throw new Error(
        reason || `"${file.name}" is ${formatBytes(file.size)} and cannot be resized automatically. Please save it as a JPG or PNG under 1 MB.`
      );
    }
    return { file, wasCompressed: false, originalBytes: file.size, finalBytes: file.size };
  };

  if (!file.type.startsWith('image/')) {
    throw new Error(`"${file.name}" is not an image.`);
  }

  if (file.type === 'image/gif') {
    return unchanged(
      `"${file.name}" is an animated image of ${formatBytes(file.size)}. Please use one under 1 MB, or save it as a JPG.`
    );
  }

  if (file.size <= TARGET_BYTES) {
    // Already small enough. Re-encoding would only lose quality for nothing.
    return { file, wasCompressed: false, originalBytes: file.size, finalBytes: file.size };
  }

  let bitmap: ImageBitmap | HTMLImageElement;
  try {
    bitmap = await loadImage(file);
  } catch {
    return unchanged(`"${file.name}" could not be read as an image.`);
  }

  const width = 'naturalWidth' in bitmap ? bitmap.naturalWidth : bitmap.width;
  const height = 'naturalHeight' in bitmap ? bitmap.naturalHeight : bitmap.height;

  if (!width || !height) {
    return unchanged(`"${file.name}" could not be read as an image.`);
  }

  const scale = Math.min(1, MAX_EDGE_PX / Math.max(width, height));
  const canvas = document.createElement('canvas');
  canvas.width = Math.max(1, Math.round(width * scale));
  canvas.height = Math.max(1, Math.round(height * scale));

  const context = canvas.getContext('2d');
  if (!context) {
    return unchanged();
  }

  context.imageSmoothingEnabled = true;
  context.imageSmoothingQuality = 'high';
  // A JPEG has no alpha channel; without this, transparent PNG areas encode as
  // black instead of white.
  context.fillStyle = '#ffffff';
  context.fillRect(0, 0, canvas.width, canvas.height);
  context.drawImage(bitmap as CanvasImageSource, 0, 0, canvas.width, canvas.height);

  if ('close' in bitmap && typeof bitmap.close === 'function') {
    bitmap.close();
  }

  let best: Blob | null = null;
  for (const quality of QUALITY_STEPS) {
    const blob = await canvasToBlob(canvas, quality);
    if (!blob) {
      continue;
    }
    best = blob;
    if (blob.size <= TARGET_BYTES) {
      break;
    }
  }

  if (!best) {
    return unchanged();
  }

  if (best.size > IMAGE_MAX_BYTES) {
    throw new Error(
      `"${file.name}" is still ${formatBytes(best.size)} after resizing. Please crop it or save it at a smaller size.`
    );
  }

  const compressed = new File([best], toJpegName(file.name), {
    type: 'image/jpeg',
    lastModified: Date.now()
  });

  return {
    file: compressed,
    wasCompressed: true,
    originalBytes: file.size,
    finalBytes: compressed.size
  };
}

/** Size-checks a non-image upload. PDFs cannot be shrunk in the browser. */
export function assertPdfWithinLimit(file: File): void {
  if (file.size > PDF_MAX_BYTES) {
    throw new Error(`"${file.name}" is ${formatBytes(file.size)}. PDF files must be 2 MB or smaller.`);
  }
}

function toJpegName(name: string): string {
  const base = name.replace(/\.[^.]+$/, '') || 'image';
  return `${base}.jpg`;
}

function canvasToBlob(canvas: HTMLCanvasElement, quality: number): Promise<Blob | null> {
  return new Promise((resolve) => canvas.toBlob(resolve, 'image/jpeg', quality));
}

async function loadImage(file: File): Promise<ImageBitmap | HTMLImageElement> {
  // createImageBitmap decodes off the main thread where it exists, which keeps
  // the UI responsive while a large photo is being read.
  if (typeof createImageBitmap === 'function') {
    try {
      return await createImageBitmap(file);
    } catch {
      // Safari historically refused some formats here; fall through.
    }
  }

  const url = URL.createObjectURL(file);
  try {
    return await new Promise<HTMLImageElement>((resolve, reject) => {
      const image = new Image();
      image.onload = () => resolve(image);
      image.onerror = () => reject(new Error('decode failed'));
      image.src = url;
    });
  } finally {
    URL.revokeObjectURL(url);
  }
}
