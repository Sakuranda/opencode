/** Decode a standard base64 string to raw bytes (binary-safe). */
export function base64ToBytes(value: string): Uint8Array<ArrayBuffer> {
  const binary = atob(value)
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i)
  return bytes
}

/** Trigger a browser download for the given blob under `filename`. */
export function triggerBrowserDownload(blob: Blob, filename: string): void {
  const url = URL.createObjectURL(blob)
  const anchor = document.createElement("a")
  anchor.href = url
  anchor.download = filename || "download"
  anchor.rel = "noopener"
  anchor.style.display = "none"
  document.body.appendChild(anchor)
  anchor.click()
  document.body.removeChild(anchor)
  // Revoke on the next tick so the click has a chance to start the download.
  setTimeout(() => URL.revokeObjectURL(url), 0)
}

/** Shape returned by the SDK `file.read` endpoint (subset we depend on). */
export interface FileReadResult {
  type: "text" | "binary"
  content: string
  encoding?: "base64"
  mimeType?: string
}

/** Convert a `file.read` result into a Blob ready for download. */
export function fileResultToBlob(result: FileReadResult): Blob {
  if (result.type === "binary" || result.encoding === "base64") {
    // `.buffer` is a plain ArrayBuffer (a valid BlobPart) because base64ToBytes
    // returns a fresh, full-length allocation covering exactly these bytes.
    return new Blob([base64ToBytes(result.content).buffer], {
      type: result.mimeType || "application/octet-stream",
    })
  }
  return new Blob([result.content], { type: result.mimeType || "text/plain;charset=utf-8" })
}

/** Last path segment, used as the default download filename. */
export function filenameFromPath(path: string): string {
  const normalized = path.replaceAll("\\", "/").replace(/\/+$/, "")
  const segment = normalized.slice(normalized.lastIndexOf("/") + 1)
  return segment || "download"
}
