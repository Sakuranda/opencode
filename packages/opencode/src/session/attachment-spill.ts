import path from "path"
import { Effect } from "effect"
import { FSUtil } from "@opencode-ai/core/fs-util"

/**
 * Spill non-inline binary attachments (Word/Excel/PowerPoint/ZIP/etc.) to disk
 * inside the session's working directory, so the AI can read them with the bash
 * tool (python-docx, openpyxl, unzip, ...) instead of receiving a useless base64
 * blob in the conversation context.
 */
export namespace AttachmentSpill {
  // Hard ceiling enforced server-side. The web UI caps uploads at 25 MB; this is
  // a defense-in-depth limit in case a client bypasses that.
  const MAX_BYTES = 50 * 1024 * 1024

  export interface Result {
    savedPath: string
    relativePath: string
    sizeBytes: number
  }

  /** Decode a data: URL to raw bytes (binary-safe, unlike the utf8 decodeDataUrl helper). */
  export function decodeBinaryDataUrl(url: string): Uint8Array {
    const idx = url.indexOf(",")
    if (idx === -1) return new Uint8Array()
    const head = url.slice(0, idx)
    const body = url.slice(idx + 1)
    if (head.includes(";base64")) return new Uint8Array(Buffer.from(body, "base64"))
    return new Uint8Array(Buffer.from(decodeURIComponent(body), "utf8"))
  }

  /** Strip path separators and unsafe characters from a user-supplied filename.
   * Unicode characters (Chinese, Japanese, etc.) are preserved. */
  export function sanitize(name: string): string {
    const base = name.split(/[\\/]/).pop() ?? "file"
    let clean = base
      // Remove NUL bytes, control characters, and shell-dangerous chars.
      // Keep Unicode letters/digits (Chinese, Japanese, etc.), spaces → underscore.
      .replace(/[\x00-\x1f\x7f]/g, "")   // control chars
      .replace(/[<>:"|?*]/g, "_")          // Windows-unsafe + shell-risky
      .replace(/\s+/g, "_")               // whitespace to underscore
      .replace(/_+/g, "_")                // collapse multiple underscores
      .replace(/^[._]+/, "")              // no leading dot/underscore
      .replace(/[._]+$/, "")              // no trailing dot/underscore
    if (!clean) clean = "file"
    if (clean.length > 200) {
      const dot = clean.lastIndexOf(".")
      const ext = dot > 0 ? clean.slice(dot) : ""
      clean = clean.slice(0, 200 - ext.length) + ext
    }
    return clean
  }

  export function humanSize(bytes: number): string {
    if (bytes < 1024) return `${bytes} B`
    const units = ["KB", "MB", "GB"]
    let value = bytes / 1024
    let unit = 0
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024
      unit += 1
    }
    return `${value.toFixed(value >= 10 || Number.isInteger(value) ? 0 : 1)} ${units[unit]}`
  }

  export const materialize = Effect.fn("AttachmentSpill.materialize")(function* (args: {
    fsys: FSUtil.Interface
    cwd: string
    sessionID: string
    partID: string
    filename: string
    url: string
  }) {
    const bytes = decodeBinaryDataUrl(args.url)
    if (bytes.byteLength === 0) return yield* Effect.fail(new Error("attachment is empty"))
    if (bytes.byteLength > MAX_BYTES)
      return yield* Effect.fail(new Error(`attachment exceeds ${MAX_BYTES} bytes`))

    const shortId = args.partID.slice(-8).replace(/[^A-Za-z0-9]/g, "") || "0"
    const name = `${shortId}-${sanitize(args.filename || "file")}`

    const dir = path.join(args.cwd, "uploads", args.sessionID)
    const savedPath = path.join(dir, name)

    // Path-traversal guard: the resolved target must stay inside the uploads dir.
    const resolved = path.resolve(savedPath)
    const baseDir = path.resolve(dir)
    if (resolved !== baseDir && !resolved.startsWith(baseDir + path.sep))
      return yield* Effect.fail(new Error("invalid attachment path"))

    yield* args.fsys.writeWithDirs(resolved, bytes)

    return {
      savedPath: resolved,
      relativePath: "./" + path.relative(args.cwd, resolved).split(path.sep).join("/"),
      sizeBytes: bytes.byteLength,
    } satisfies Result
  })
}
