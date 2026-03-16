// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Modifications for iOS / Swift adaptation by WGGao (BA3QT).
import AVFoundation
import Foundation

protocol InternalSampleProvider: AnyObject {
    func nextInternalAudioBlock() -> [Float]
}

final class ContestAudioPlayer {
    private weak var provider: InternalSampleProvider?
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?

    private let bufferLock = NSLock()
    private let producerQueue = DispatchQueue(label: "CWRunner.audio.producer", qos: .userInitiated)
    private let ringCapacity = 16_384
    private let targetBufferedSamples = 4_096
    private let refillThreshold = 2_048

    private var ringBuffer: [Float]
    private var readIndex = 0
    private var writeIndex = 0
    private var availableSamples = 0
    private var internalFraction = 0.0
    private var playbackActive = false
    private var producerScheduled = false
    private let internalRate = defaultSampleRate

    init(provider: InternalSampleProvider) {
        self.provider = provider
        self.ringBuffer = Array(repeating: 0, count: ringCapacity)
        setupSession()
        setupEngine()
    }

    func start() {
        resetBufferState(playbackActive: true)
        scheduleProducerIfNeeded(force: true)
        activateEngineIfNeeded()
    }

    func resume() {
        bufferLock.lock()
        playbackActive = true
        internalFraction = 0
        bufferLock.unlock()
        scheduleProducerIfNeeded(force: true)
        activateEngineIfNeeded()
    }

    func pause() {
        bufferLock.lock()
        playbackActive = false
        producerScheduled = false
        bufferLock.unlock()
        engine.pause()
    }

    func appOutputVolume() -> Float {
        engine.mainMixerNode.outputVolume
    }

    func setAppOutputVolume(_ value: Float) {
        engine.mainMixerNode.outputVolume = clamp(value, lower: 0, upper: 1)
    }

    private func activateEngineIfNeeded() {
        guard !engine.isRunning else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            engine.prepare()
            try engine.start()
        } catch {
            print("Audio start failed: \(error)")
        }
    }

    func stop() {
        resetBufferState(playbackActive: false)
        engine.pause()
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        } catch {
            print("Audio stop failed: \(error)")
        }
    }

    private func setupSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        } catch {
            print("Audio session setup failed: \(error)")
        }
    }

    private func setupEngine() {
        let sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!

        let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
            self?.render(to: audioBufferList, frames: Int(frameCount), outputRate: sampleRate)
            return noErr
        }

        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 0.9
    }

    private func render(to audioBufferList: UnsafeMutablePointer<AudioBufferList>, frames: Int, outputRate: Double) {
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let ratio = internalRate / outputRate

        for frame in 0..<frames {
            let sample = nextSample(ratio: ratio)
            for buffer in buffers {
                let pointer = buffer.mData?.assumingMemoryBound(to: Float.self)
                pointer?[frame] = sample
            }
        }
    }

    private func nextSample(ratio: Double) -> Float {
        var sample: Float = 0
        var needsRefill = false

        bufferLock.lock()
        if availableSamples >= 2 {
            let current = ringBuffer[readIndex]
            let next = ringBuffer[(readIndex + 1) % ringCapacity]
            sample = current + (next - current) * Float(internalFraction)

            internalFraction += ratio
            let advanced = Int(internalFraction)
            if advanced > 0 {
                let step = min(advanced, max(availableSamples - 1, 0))
                readIndex = (readIndex + step) % ringCapacity
                availableSamples -= step
                internalFraction -= Double(step)
            }
        } else if availableSamples == 1 {
            sample = ringBuffer[readIndex]
        }

        needsRefill = playbackActive && availableSamples < refillThreshold
        bufferLock.unlock()

        if needsRefill {
            scheduleProducerIfNeeded()
        }
        return clamp(sample / 32_768, lower: -1, upper: 1)
    }

    private func resetBufferState(playbackActive: Bool) {
        bufferLock.lock()
        self.playbackActive = playbackActive
        producerScheduled = false
        readIndex = 0
        writeIndex = 0
        availableSamples = 0
        internalFraction = 0
        ringBuffer = Array(repeating: 0, count: ringCapacity)
        bufferLock.unlock()
    }

    private func scheduleProducerIfNeeded(force: Bool = false) {
        var shouldSchedule = false

        bufferLock.lock()
        if playbackActive && !producerScheduled && (force || availableSamples < targetBufferedSamples) {
            producerScheduled = true
            shouldSchedule = true
        }
        bufferLock.unlock()

        guard shouldSchedule else { return }

        producerQueue.async { [weak self] in
            self?.fillRingBuffer()
        }
    }

    private func fillRingBuffer() {
        while true {
            guard let provider else {
                bufferLock.lock()
                producerScheduled = false
                bufferLock.unlock()
                return
            }

            bufferLock.lock()
            let shouldContinue = playbackActive && availableSamples < targetBufferedSamples
            bufferLock.unlock()

            guard shouldContinue else {
                bufferLock.lock()
                producerScheduled = false
                bufferLock.unlock()
                return
            }

            let block = provider.nextInternalAudioBlock()

            bufferLock.lock()
            for sample in block {
                guard availableSamples < ringCapacity else { break }
                ringBuffer[writeIndex] = sample
                writeIndex = (writeIndex + 1) % ringCapacity
                availableSamples += 1
            }
            bufferLock.unlock()
        }
    }
}
