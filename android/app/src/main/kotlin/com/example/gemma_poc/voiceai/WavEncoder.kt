package com.example.gemma_poc.voiceai

import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * LiteRT-LM audio preprocessor uses miniaudio, which requires WAV/FLAC/MP3 —
 * raw PCM alone fails with miniaudio error -10.
 */
object WavEncoder {
    fun pcm16MonoToWav(
        pcm: ByteArray,
        sampleRateHz: Int = 16_000,
    ): ByteArray {
        val channels = 1
        val bitsPerSample = 16
        val byteRate = sampleRateHz * channels * bitsPerSample / 8
        val blockAlign = channels * bitsPerSample / 8
        val dataSize = pcm.size
        val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)

        header.put("RIFF".toByteArray(Charsets.US_ASCII))
        header.putInt(36 + dataSize)
        header.put("WAVE".toByteArray(Charsets.US_ASCII))
        header.put("fmt ".toByteArray(Charsets.US_ASCII))
        header.putInt(16) // PCM chunk size
        header.putShort(1) // PCM format
        header.putShort(channels.toShort())
        header.putInt(sampleRateHz)
        header.putInt(byteRate)
        header.putShort(blockAlign.toShort())
        header.putShort(bitsPerSample.toShort())
        header.put("data".toByteArray(Charsets.US_ASCII))
        header.putInt(dataSize)

        return header.array() + pcm
    }
}
