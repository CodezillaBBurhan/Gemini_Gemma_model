# gemma_poc

Fully **on-device** Gemma 3n voice-to-text Flutter POC using Google AI Edge **LiteRT-LM**.

- No Gemini API / Cloud Speech / backend inference
- Microphone → local PCM chunks → Gemma 3n → transcript UI
- Works offline after the official model is downloaded once

See **[ON_DEVICE_AI_SETUP.md](ON_DEVICE_AI_SETUP.md)** for model source, native setup, offline testing, and known limitations.
