# Gemma 3n Mobile Audio — Capability Verification

Date: 2026-08-11  
Sources: Google AI Edge LiteRT-LM docs, MediaPipe LLM Inference (maintenance-only), Gemma 3n developer guide.

## Verdict

| Requirement | Reality |
|---|---|
| Fully on-device inference | Yes (LiteRT-LM) |
| Gemma 3n audio input | Yes (multimodal `.litertlm`) |
| Continuous real-time STT stream | **No** — not a first-class mobile ASR stream today |
| Progressive UI updates | Yes — via **chunked** clip inference + token streaming per clip |
| Airplane Mode after model install | Yes |

## Chosen model

**Gemma 3n E2B int4** (`.litertlm`) over E4B for mobile RAM/latency.

## Implemented pipeline

Chunked on-device transcription (documented honestly; not fake continuous ASR).
