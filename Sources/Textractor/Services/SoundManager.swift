//
//  SoundManager.swift
//  Textractor
//
//  Synthesized auditory feedback using Core Audio.
//  Cyberpunk-style electronic blips — no external sound files needed.
//

import Cocoa
import AudioToolbox
import CoreAudio

enum SoundManager {

    /// Master gate. `false` makes every public sounding entry a no-op so user
    /// changes in Settings propagate immediately without restarting anything.
    static var enabled: Bool = true

    static func playCaptureStart() {
        guard enabled else { return }
        // Short rising blip — like a scanner powering up
        playTone(frequency: 880, duration: 0.06, volume: 0.15)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.04) {
            playTone(frequency: 1320, duration: 0.05, volume: 0.12)
        }
    }

    /// Convenience used by AppCoordinator when the user's sound toggle changes
    /// mid-session: propagate without code churn at call sites.
    static func playCaptureStartIfEnabled() {
        playCaptureStart()
    }

    static func playCaptureComplete() {
        guard enabled else { return }
        // Pleasant two-note confirmation — cyberpunk UI sound
        playTone(frequency: 1046.5, duration: 0.05, volume: 0.15) // C6
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
            playTone(frequency: 1568, duration: 0.08, volume: 0.13) // G6
        }
    }

    /// Subtle, professional — played when the user toggles mode (crosshair ↔ window).
    static func playModeTick() {
        guard enabled else { return }
        playTone(frequency: 1480, duration: 0.025, volume: 0.08)
    }

    /// Soft tick when a capture starts scrolling / drag begins.
    static func playClick() {
        guard enabled else { return }
        playTone(frequency: 980, duration: 0.018, volume: 0.06)
    }

    static func playCancel() {
        guard enabled else { return }
        playTone(frequency: 320, duration: 0.07, volume: 0.10)
    }

    static func playError() {
        guard enabled else { return }
        // Low buzz — error/alert
        playTone(frequency: 200, duration: 0.12, volume: 0.15)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            playTone(frequency: 150, duration: 0.15, volume: 0.12)
        }
    }

    // MARK: - Tone Synthesis

    private static func playTone(frequency: Double, duration: Double, volume: Float) {
        let sampleRate: Double = 44100
        let totalSamples = Int(sampleRate * duration)
        let totalBytes = totalSamples * 2 // 16-bit mono

        var data = Data(count: totalBytes)
        data.withUnsafeMutableBytes { ptr in
            let buf = ptr.bindMemory(to: Int16.self)
            for i in 0..<totalSamples {
                let t = Double(i) / sampleRate
                // Envelope: quick attack, exponential decay
                let envelope = exp(-t * 8.0) * (1.0 - exp(-t * 100.0))
                let sample = Int16(min(1.0, envelope * Double(volume)) * Double(Int16.max) * sin(2.0 * .pi * frequency * t))
                buf[i] = sample
            }
        }

        playDataAsSound(data, sampleRate: sampleRate)
    }

    private static func playDataAsSound(_ data: Data, sampleRate: Double) {
        // Build a WAV file in memory and play via NSSound
        var wavData = Data()

        var chunkSize: UInt32 = UInt32(data.count + 36)
        var audioFormat: UInt16 = 1 // PCM
        var numChannels: UInt16 = 1
        var sampleRateVal = UInt32(sampleRate)
        var byteRate: UInt32 = UInt32(sampleRate) * 2
        var blockAlign: UInt16 = 2
        var bitsPerSample: UInt16 = 16
        var dataLen = UInt32(data.count)

        // RIFF header
        wavData.append("RIFF".data(using: .ascii)!)
        withUnsafeBytes(of: &chunkSize) { wavData.append(contentsOf: $0) }
        wavData.append("WAVE".data(using: .ascii)!)

        // fmt subchunk
        wavData.append("fmt ".data(using: .ascii)!)
        var subchunk1Size: UInt32 = 16
        withUnsafeBytes(of: &subchunk1Size) { wavData.append(contentsOf: $0) }
        withUnsafeBytes(of: &audioFormat)    { wavData.append(contentsOf: $0) }
        withUnsafeBytes(of: &numChannels)    { wavData.append(contentsOf: $0) }
        withUnsafeBytes(of: &sampleRateVal)  { wavData.append(contentsOf: $0) }
        withUnsafeBytes(of: &byteRate)       { wavData.append(contentsOf: $0) }
        withUnsafeBytes(of: &blockAlign)     { wavData.append(contentsOf: $0) }
        withUnsafeBytes(of: &bitsPerSample)  { wavData.append(contentsOf: $0) }

        // data subchunk
        wavData.append("data".data(using: .ascii)!)
        withUnsafeBytes(of: &dataLen) { wavData.append(contentsOf: $0) }
        wavData.append(data)

        if let sound = NSSound(data: wavData) {
            sound.volume = 0.5
            sound.play()
        }
    }
}
