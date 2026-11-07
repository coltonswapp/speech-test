import assert from "node:assert/strict";
import { describe, it } from "node:test";
import { contentDispositionAttachment, downloadFilename } from "./download";

describe("contentDispositionAttachment", () => {
  it("puts Japanese titles in filename* and keeps filename ASCII", () => {
    const header = contentDispositionAttachment(
      downloadFilename("こんにちは", ".mp3"),
    );
    assert.match(header, /^attachment; filename="[^"]+"; filename\*=UTF-8''/);
    assert.equal(header.includes("こんにちは"), false);
    assert.match(header, /filename\*=UTF-8''.*%E3%81%93/);
    assert.match(header, /\.mp3/);
    const headers = new Headers();
    headers.set("Content-Disposition", header);
    assert.equal(headers.get("Content-Disposition"), header);
  });

  it("does the same for timing JSON", () => {
    const header = contentDispositionAttachment(
      downloadFilename("挨拶の録音", ".json"),
    );
    const headers = new Headers();
    headers.set("Content-Disposition", header);
    assert.match(header, /filename\*=UTF-8''/);
    assert.match(header, /\.json/);
    assert.equal(header.includes("挨拶"), false);
  });

  it("rejects interpolating Japanese into filename= via Headers", () => {
    const headers = new Headers();
    assert.throws(
      () =>
        headers.set(
          "Content-Disposition",
          `attachment; filename="${downloadFilename("こんにちは", ".mp3")}"`,
        ),
      /ByteString|Invalid character|incorrect header/i,
    );
  });
});
