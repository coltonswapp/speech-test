export type ScatterPhoto = {
  photoId: string;
  url: string;
  rotate: number;
  x: number;
  y: number;
  width: number;
  height: number;
  z: number;
};

export type PoolPhoto = {
  id: string;
  url: string;
};

function mulberry32(seed: number): () => number {
  let t = seed >>> 0;
  return () => {
    t += 0x6d2b79f5;
    let r = Math.imul(t ^ (t >>> 15), t | 1);
    r ^= r + Math.imul(r ^ (r >>> 7), r | 61);
    return ((r ^ (r >>> 14)) >>> 0) / 4294967296;
  };
}

function hashSeed(seed: number, slideIndex: number): number {
  return (Math.imul(seed, 0x9e3779b1) ^ Math.imul(slideIndex + 1, 0x85ebca6b)) >>> 0;
}

export function pickWashPhoto(
  photos: PoolPhoto[],
  seed: number,
  slideIndex: number
): PoolPhoto | null {
  if (photos.length === 0) return null;
  const rand = mulberry32(hashSeed(seed, slideIndex));
  return photos[Math.floor(rand() * photos.length)] ?? null;
}

export function scatterForSlide(params: {
  photos: PoolPhoto[];
  seed: number;
  slideIndex: number;
  count: number;
}): ScatterPhoto[] {
  const { photos, seed, slideIndex, count } = params;
  if (photos.length === 0 || count <= 0) return [];
  const rand = mulberry32(hashSeed(seed, slideIndex));
  const used = new Set<string>();
  const out: ScatterPhoto[] = [];
  const n = Math.min(count, Math.max(1, photos.length));
  for (let i = 0; i < n; i += 1) {
    let photo = photos[Math.floor(rand() * photos.length)];
    let guard = 0;
    while (used.has(photo.id) && used.size < photos.length && guard < 8) {
      photo = photos[Math.floor(rand() * photos.length)];
      guard += 1;
    }
    used.add(photo.id);
    out.push({
      photoId: photo.id,
      url: photo.url,
      rotate: rand() * 16 - 8,
      x: rand() * 36 - 18,
      y: rand() * 36 - 18,
      width: 88 + rand() * 28,
      height: 88 + rand() * 28,
      z: i,
    });
  }
  return out;
}

export function newPhotoSeed(): number {
  return Math.floor(Math.random() * 0x7fffffff);
}
