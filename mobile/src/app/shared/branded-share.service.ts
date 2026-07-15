import { Injectable } from '@angular/core';
import { Capacitor } from '@capacitor/core';
import { Directory, Filesystem } from '@capacitor/filesystem';
import { Share } from '@capacitor/share';

/**
 * Shares any chart canvas as a branded PNG: the chart is composited under a
 * CoachFlow Studio header (logo mark + wordmark + chart title) and a footer
 * strip, then handed to the native Android share sheet (or Web Share /
 * download in a browser).
 */
@Injectable({ providedIn: 'root' })
export class BrandedShareService {
  async shareChart(sourceCanvas: HTMLCanvasElement, title: string, subtitle = ''): Promise<void> {
    const branded = this.compose(sourceCanvas, title, subtitle);
    const fileName = `coachflow-${title.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '') || 'chart'}.png`;

    if (Capacitor.isNativePlatform()) {
      const base64 = branded.toDataURL('image/png').split(',')[1];
      const file = await Filesystem.writeFile({
        path: fileName,
        data: base64,
        directory: Directory.Cache
      });
      await Share.share({
        title: `${title} — CoachFlow Studio`,
        text: subtitle ? `${title} · ${subtitle}` : title,
        files: [file.uri]
      });
      return;
    }

    const blob = await new Promise<Blob | null>((resolve) => branded.toBlob(resolve, 'image/png'));

    if (!blob) {
      return;
    }

    const file = new File([blob], fileName, { type: 'image/png' });
    const nav = navigator as Navigator & { canShare?: (data: ShareData) => boolean };

    if (nav.share && nav.canShare?.({ files: [file] })) {
      try {
        await nav.share({ files: [file], title: `${title} — CoachFlow Studio` });
        return;
      } catch {
        // fall through to download when the user cancels is fine; other
        // failures also fall back to a plain download.
      }
    }

    const url = URL.createObjectURL(blob);
    const anchor = document.createElement('a');
    anchor.href = url;
    anchor.download = fileName;
    anchor.click();
    URL.revokeObjectURL(url);
  }

  /** Draws header (logo + wordmark + title), the chart, and a footer note. */
  private compose(source: HTMLCanvasElement, title: string, subtitle: string): HTMLCanvasElement {
    const scale = 2;
    const width = Math.max(640, source.width);
    const headerHeight = 96 * scale;
    const footerHeight = 34 * scale;
    const pad = 16 * scale;

    const target = document.createElement('canvas');
    target.width = width + pad * 2;
    target.height = headerHeight + source.height + footerHeight + pad;
    const ctx = target.getContext('2d');

    if (!ctx) {
      return source;
    }

    const isDark = window.matchMedia?.('(prefers-color-scheme: dark)').matches;
    const bg = isDark ? '#101820' : '#ffffff';
    const text = isDark ? '#f6f9fc' : '#122033';
    const muted = isDark ? '#adbac8' : '#64748b';
    const primary = isDark ? '#58a6ff' : '#0b7de3';

    ctx.fillStyle = bg;
    ctx.fillRect(0, 0, target.width, target.height);

    // Brand mark: rounded square + dumbbell strokes (same glyph as the web brand).
    const markSize = 44 * scale;
    const markX = pad;
    const markY = 20 * scale;
    ctx.fillStyle = primary;
    this.roundRect(ctx, markX, markY, markSize, markSize, 12 * scale);
    ctx.fill();

    ctx.strokeStyle = '#ffffff';
    ctx.lineWidth = 2.4 * scale;
    ctx.lineCap = 'round';
    const unit = markSize / 24;
    const gx = (v: number): number => markX + v * unit;
    const gy = (v: number): number => markY + v * unit;
    ctx.beginPath();
    ctx.moveTo(gx(6), gy(8)); ctx.lineTo(gx(6), gy(16));
    ctx.moveTo(gx(18), gy(8)); ctx.lineTo(gx(18), gy(16));
    ctx.moveTo(gx(6), gy(12)); ctx.lineTo(gx(18), gy(12));
    ctx.moveTo(gx(3.5), gy(9.5)); ctx.lineTo(gx(3.5), gy(14.5));
    ctx.moveTo(gx(20.5), gy(9.5)); ctx.lineTo(gx(20.5), gy(14.5));
    ctx.stroke();

    const textX = markX + markSize + 12 * scale;
    ctx.fillStyle = text;
    ctx.font = `800 ${15 * scale}px system-ui, -apple-system, sans-serif`;
    ctx.fillText('CoachFlow Studio', textX, markY + 17 * scale);
    ctx.fillStyle = muted;
    ctx.font = `600 ${10 * scale}px system-ui, -apple-system, sans-serif`;
    ctx.fillText('Trainer & Client Management Platform', textX, markY + 32 * scale);

    ctx.fillStyle = text;
    ctx.font = `800 ${13 * scale}px system-ui, -apple-system, sans-serif`;
    ctx.fillText(title, pad, headerHeight - 10 * scale);

    if (subtitle) {
      ctx.fillStyle = muted;
      ctx.font = `600 ${10 * scale}px system-ui, -apple-system, sans-serif`;
      const titleWidth = ctx.measureText(title).width;
      ctx.fillText(subtitle, pad + titleWidth + 60, headerHeight - 10 * scale);
    }

    ctx.strokeStyle = isDark ? '#2f4358' : '#d7e5f5';
    ctx.lineWidth = scale;
    ctx.beginPath();
    ctx.moveTo(pad, headerHeight - 4 * scale);
    ctx.lineTo(target.width - pad, headerHeight - 4 * scale);
    ctx.stroke();

    // Chart body on a card-colored background so transparent canvases read well.
    ctx.fillStyle = isDark ? '#172230' : '#ffffff';
    ctx.fillRect(pad, headerHeight, width, source.height);
    ctx.drawImage(source, pad + (width - source.width) / 2, headerHeight);

    ctx.fillStyle = muted;
    ctx.font = `600 ${9 * scale}px system-ui, -apple-system, sans-serif`;
    ctx.fillText(`Generated ${new Date().toLocaleDateString()} · coachflow.studio`, pad, target.height - 12 * scale);

    return target;
  }

  private roundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number): void {
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.arcTo(x + w, y, x + w, y + h, r);
    ctx.arcTo(x + w, y + h, x, y + h, r);
    ctx.arcTo(x, y + h, x, y, r);
    ctx.arcTo(x, y, x + w, y, r);
    ctx.closePath();
  }
}
