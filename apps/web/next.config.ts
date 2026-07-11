import type { NextConfig } from "next";
import path from "path";

const nextConfig: NextConfig = {
  // Standalone-Output nur im Docker-Build (Coolify) — dort setzt das Dockerfile
  // NEXT_OUTPUT_STANDALONE=1. Lokal/CI (v.a. Windows) bleibt der Standalone-Copy-Schritt
  // aus, der an ':' in Turbopack-Chunknamen (node:inspector) auf Windows scheitert.
  output: process.env.NEXT_OUTPUT_STANDALONE === "1" ? "standalone" : undefined,
  // Monorepo: Tracing ab Repo-Root, damit node_modules korrekt mitkopiert werden.
  outputFileTracingRoot: path.join(process.cwd(), "../../"),
  // Native Module nicht bundeln, sondern extern lassen (Datei-Tracing kopiert das .node).
  serverExternalPackages: ["better-sqlite3"],
};

export default nextConfig;
