/**
 * Reads an image File, downscales it, and resolves a compressed JPEG data URL.
 * Used for client display photos and tracking-entry images so uploads stay
 * small enough to store inline (base64) without a file backend.
 */
export function readImageAsDataUrl(file: File, maxSize = 512): Promise<string> {
  return new Promise((resolve, reject) => {
    if (!file.type.startsWith('image/')) {
      reject(new Error('Selected file is not an image.'));
      return;
    }

    const reader = new FileReader();
    reader.onerror = () => reject(new Error('Could not read the image.'));
    reader.onload = () => {
      const image = new Image();
      image.onerror = () => reject(new Error('Could not load the image.'));
      image.onload = () => {
        const scale = Math.min(1, maxSize / Math.max(image.width, image.height));
        const canvas = document.createElement('canvas');
        canvas.width = Math.round(image.width * scale);
        canvas.height = Math.round(image.height * scale);
        canvas.getContext('2d')?.drawImage(image, 0, 0, canvas.width, canvas.height);
        resolve(canvas.toDataURL('image/jpeg', 0.7));
      };
      image.src = String(reader.result || '');
    };
    reader.readAsDataURL(file);
  });
}
