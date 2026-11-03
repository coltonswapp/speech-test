// Minimal 16-bit PCM WAV writer/reader — mono, matches what OpenAI's
// response_format=pcm and Gemini's inlineData audio both return (raw
// 16-bit signed LE PCM), and what TrimmedAudioExport.swift writes on the
// Mac side, so files are byte-compatible across both apps.

export function pcm16ToWav(pcm: Buffer, sampleRate: number): Buffer {
  const dataSize = pcm.length;
  const header = Buffer.alloc(44);
  header.write("RIFF", 0, "ascii");
  header.writeUInt32LE(36 + dataSize, 4);
  header.write("WAVE", 8, "ascii");
  header.write("fmt ", 12, "ascii");
  header.writeUInt32LE(16, 16); // fmt chunk size
  header.writeUInt16LE(1, 20); // PCM format
  header.writeUInt16LE(1, 22); // mono
  header.writeUInt32LE(sampleRate, 24);
  header.writeUInt32LE(sampleRate * 2, 28); // byte rate (16-bit mono)
  header.writeUInt16LE(2, 32); // block align
  header.writeUInt16LE(16, 34); // bits per sample
  header.write("data", 36, "ascii");
  header.writeUInt32LE(dataSize, 40);
  return Buffer.concat([header, pcm]);
}

/**
 * Finds the `fmt ` and `data` chunks by walking the RIFF chunk list. Gemini
 * 3.8 TTS returns WAV with a C2PA provenance chunk *after* `data`, so slicing
 * at byte 44 would append that metadata to the audio as noise.
 */
function parseWavChunks(wav: Buffer): { pcm: Buffer; sampleRate: number } {
  let sampleRate = 0;
  let offset = 12;
  while (offset + 8 <= wav.length) {
    const id = wav.toString("ascii", offset, offset + 4);
    const size = wav.readUInt32LE(offset + 4);
    const body = offset + 8;
    if (id === "fmt " && body + 8 <= wav.length) {
      sampleRate = wav.readUInt32LE(body + 4);
    } else if (id === "data") {
      const end = Math.min(body + size, wav.length);
      return { pcm: wav.subarray(body, end), sampleRate };
    }
    offset = body + size + (size % 2);
  }
  throw new Error("WAV has no data chunk");
}

export function wavToPcm16(wav: Buffer): { pcm: Buffer; sampleRate: number } {
  if (wav.length < 44 || wav.toString("ascii", 0, 4) !== "RIFF") {
    throw new Error("Not a WAV file");
  }
  return parseWavChunks(wav);
}

/**
 * Gemini TTS audio as raw 16-bit PCM: 3.1 and earlier return headerless
 * `audio/l16`; 3.8+ returns `audio/wav`, which is unwrapped here.
 */
export function geminiAudioToPcm16(data: Buffer): Buffer {
  if (data.length > 12 && data.toString("ascii", 0, 4) === "RIFF") {
    return parseWavChunks(data).pcm;
  }
  return data;
}

export function pcm16ToFloat32(pcm: Buffer): Float32Array {
  const sampleCount = pcm.length / 2;
  const out = new Float32Array(sampleCount);
  for (let i = 0; i < sampleCount; i++) {
    out[i] = pcm.readInt16LE(i * 2) / 32768;
  }
  return out;
}
