# Offline PDF Reader & Study Companion

A private, distraction-free document reader and archival study studio designed for Android. Built with Flutter, featuring a responsive white dragon study companion and 100% on-device local GGUF AI inference.

---

## Key Features

### 1. Quiet Editorial Document Studio
- **Distraction-Free Reading:** Continuous scroll and single-page display tuned with warm editorial palettes (Terracotta, Slate Teal, Cream).
- **Rich Annotations:** Highlights, underlines, strikethroughs, freehand drawing, handwritten signatures, and sticky notes saved to private SQLite storage.
- **Bookmarks & Navigation:** Interactive page thumbnail scrubber, jump-to-page, and instant full-text search.
- **Text-to-Speech (TTS):** Offline read-aloud support with speech rate control and background playback.
- **On-Device OCR:** Optical character recognition powered by Google ML Kit Latin models for scanned documents and images.

### 2. White Dragon Study Companion (`Chiku`)
- **Lightweight Interactive Overlay:** Smooth 56px floating companion positioned above the bottom toolbar without obstructing document reading gestures.
- **Dynamic Animation States:** 12 expressive transparent states including idle breathing, periodic blinking, reading, thinking, curious, explaining, and sleeping.
- **Quick Action Sheet:** Tap the companion to access document Q&A, explain selected text, launch Study Mode, summarize the current page, or manage offline models.

### 3. True On-Device Local LLM Intelligence
- **Private Offline Inference:** High-performance local language model inference powered by `llama.cpp` and `llama_flutter_android`. Zero telemetry or cloud requests.
- **Grounded Document Q&A:** RAG-grounded answers citing exact source pages. Falls back to deterministic extraction if evidence is insufficient or when models are uninstalled.
- **Downloadable GGUF Models:**
  - **Qwen3 1.7B Q4_K_M (Primary):** ~1.28 GB, 2048 context window. High quality explanations, revision notes, and exam question generation.
  - **Qwen3 0.6B Q4_0 (Quick Option):** ~429 MB, 1024/2048 context window. Lower-memory model suited for lightweight devices.
- **Security & Integrity:** Resumable chunked downloads verified against strict SHA-256 digests before installation. Automatic model unloading to preserve device RAM.

### 4. Power-User PDF Tools
- **Document Manipulations:** Merge multiple PDFs, split documents, extract or delete page ranges.
- **Compression & Optimization:** Target-size PDF compression and image compressor.
- **Security & Metadata:** PDF encryption with password protection and metadata inspector/editor.
- **Version History & Diff:** Track document revisions with side-by-side comparison.

---

## Technical Specifications

- **Framework:** Flutter 3.24 (Dart 3.5)
- **Min Android SDK:** 26 (Android 8.0 Oreo)
- **Target Android SDK:** 34 / 36
- **Android NDK:** 27.0.12077973
- **Inference Backend:** llama.cpp Vulkan / CPU (ARM64-v8a, armeabi-v7a, x86_64)
- **Database Schema:** SQLite Version 7 (`DatabaseHelper`)
