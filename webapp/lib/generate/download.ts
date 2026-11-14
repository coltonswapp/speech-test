/**
 * Content-Disposition for downloads. HTTP header values are ByteString, so a
 * Japanese title cannot go in `filename="..."`. ASCII fallback + RFC 5987
 * `filename*` carries the real name.
 */
export function contentDispositionAttachment(filename: string): string {
  const safe = filename.replace(/[\r\n"]/g, "").replace(/[\\/]/g, "_").trim();
  const utf8Name = safe || "download";
  const ascii = utf8Name.replace(/[^\x20-\x7E]/g, "_").replace(/_+/g, "_");
  const asciiName = /[A-Za-z0-9]/.test(ascii.replace(/\.[A-Za-z0-9]+$/, ""))
    ? ascii
    : fallbackAscii(utf8Name);
  return `attachment; filename="${asciiName}"; filename*=UTF-8''${encodeRFC5987(utf8Name)}`;
}

function fallbackAscii(filename: string): string {
  const ext = filename.match(/(\.[A-Za-z0-9]{1,8})$/)?.[1] ?? "";
  return `clip${ext}`;
}

function encodeRFC5987(value: string): string {
  return encodeURIComponent(value).replace(/['()*]/g, (char) =>
    `%${char.charCodeAt(0).toString(16).toUpperCase()}`,
  );
}

export function downloadFilename(title: string, ext: string): string {
  const trimmed = title.replace(/[\r\n]/g, " ").trim() || "clip";
  const suffix = ext.startsWith(".") ? ext : `.${ext}`;
  return trimmed.endsWith(suffix) ? trimmed : `${trimmed}${suffix}`;
}
