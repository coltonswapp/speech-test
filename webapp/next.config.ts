import path from "node:path";
import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  env: {
    // KA-9: stamped tokenSyncs record which Studio build made them.
    NEXT_PUBLIC_BUILD_SHA:
      process.env.VERCEL_GIT_COMMIT_SHA?.slice(0, 7) ?? "dev",
  },
  turbopack: {
    root: path.resolve(__dirname),
  },
  serverExternalPackages: ["@ffmpeg-installer/ffmpeg"],
};

export default nextConfig;
