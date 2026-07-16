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

export function wavToPcm16(wav: Buffer): { pcm: Buffer; sampleRate: number } {
  if (wav.length < 44 || wav.toString("ascii", 0, 4) !== "RIFF") {
    throw new Error("Not a WAV file");
  }
  const sampleRate = wav.readUInt32LE(24);
  // Assumes the canonical 44-byte header this module writes (no extra chunks).
  const pcm = wav.subarray(44);
  return { pcm, sampleRate };
}

export function pcm16ToFloat32(pcm: Buffer): Float32Array {
  const sampleCount = pcm.length / 2;
  const out = new Float32Array(sampleCount);
  for (let i = 0; i < sampleCount; i++) {
    out[i] = pcm.readInt16LE(i * 2) / 32768;
  }
  return out;
}
