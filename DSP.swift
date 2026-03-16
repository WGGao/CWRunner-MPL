// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Modifications for iOS / Swift adaptation by WGGao (BA3QT).
import Foundation

let defaultSampleRate: Double = 8_000
let twoPi: Float = .pi * 2
let neverTimeout = Int.max

struct ComplexSample {
    var re: Float
    var im: Float
}

struct ComplexBuffer {
    var re: [Float]
    var im: [Float]

    init(count: Int) {
        re = Array(repeating: 0, count: count)
        im = Array(repeating: 0, count: count)
    }

    mutating func resizeIfNeeded(count: Int) {
        guard re.count != count || im.count != count else { return }
        re = Array(repeating: 0, count: count)
        im = Array(repeating: 0, count: count)
    }
}

func ensureFloatBuffer(_ buffer: inout [Float], count: Int) {
    guard buffer.count != count else { return }
    buffer = Array(repeating: 0, count: count)
}

func clamp<T: Comparable>(_ value: T, lower: T, upper: T) -> T {
    min(upper, max(lower, value))
}

struct FastRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E37_79B9_7F4A_7C15 : seed
    }

    mutating func nextUInt64() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func nextUnitFloat() -> Float {
        Float(nextUInt64() >> 40) / Float(1 << 24)
    }

    mutating func nextSignedFloat() -> Float {
        nextUnitFloat() * 2 - 1
    }
}

enum RandomTools {
    static func normal() -> Float {
        while true {
            let u1 = max(Float.random(in: 0..<1), 1e-6)
            let u2 = Float.random(in: 0..<1)
            return sqrt(-2 * log(u1)) * cos(twoPi * u2)
        }
    }

    static func gaussLimited(mean: Float, limit: Float) -> Float {
        let value = mean + normal() * 0.5 * limit
        return clamp(value, lower: mean - limit, upper: mean + limit)
    }

    static func rayleigh(mean: Float) -> Float {
        let u1 = max(Float.random(in: 0..<1), 1e-6)
        let u2 = max(Float.random(in: 0..<1), 1e-6)
        return mean * sqrt(-log(u1) - log(u2))
    }

    static func uniform() -> Float {
        Float.random(in: -1...1)
    }

    static func uShaped() -> Float {
        sin(.pi * (Float.random(in: 0..<1) - 0.5))
    }

    static func poisson(mean: Float) -> Int {
        let g = exp(-mean)
        var t: Float = 1
        for value in 0...30 {
            t *= Float.random(in: 0..<1)
            if t <= g {
                return value
            }
        }
        return 30
    }

    static func secondsToBlocks(_ seconds: Float, bufferSize: Int) -> Int {
        Int(round(defaultSampleRate / Double(bufferSize) * Double(seconds)))
    }

    static func blocksToSeconds(_ blocks: Double, bufferSize: Int) -> Double {
        blocks * Double(bufferSize) / defaultSampleRate
    }
}

final class MorseKeyer {
    private let morseTable: [Character: String] = [
        "1": ".---- ", "2": "..--- ", "3": "...-- ", "4": "....- ", "5": "..... ",
        "6": "-.... ", "7": "--... ", "8": "---.. ", "9": "----. ", "0": "----- ",
        "A": ".- ", "B": "-... ", "C": "-.-. ", "D": "-.. ", "E": ". ", "F": "..-. ",
        "G": "--. ", "H": ".... ", "I": ".. ", "J": ".--- ", "K": "-.- ", "L": ".-.. ",
        "M": "-- ", "N": "-. ", "O": "--- ", "P": ".--. ", "Q": "--.- ", "R": ".-. ",
        "S": "... ", "T": "- ", "U": "..- ", "V": "...- ", "W": ".-- ", "X": "-..- ",
        "Y": "-.-- ", "Z": "--.. ", "/": "-..-. ", ".": ".-.-.- ", ",": "--..-- ",
        "?": "..--.. ", "=": "-...- ", "\\": "...-. "
    ]

    var rate: Int = Int(defaultSampleRate)
    var riseTime: Float = 0.005 {
        didSet { makeRamp() }
    }

    private var rampOn: [Float] = []
    private var rampOff: [Float] = []
    private var rampLength: Int = 0

    init() {
        makeRamp()
    }

    func encode(_ text: String) -> String {
        var result = ""
        for character in text.uppercased() {
            if character == " " || character == "_" {
                result.append(" ")
            } else if let morse = morseTable[character] {
                result.append(morse)
            }
        }
        if !result.isEmpty {
            result.removeLast()
            result.append("~")
        }
        return result
    }

    func envelope(for morseMessage: String, wpm: Int, amplitude: Float, blockSize: Int) -> [Float] {
        let samplesPerUnit = max(1, Int(round(0.1 * Double(rate) * 12 / Double(max(1, wpm)))))
        var unitCount = 0

        for character in morseMessage {
            switch character {
            case ".":
                unitCount += 2
            case "-":
                unitCount += 4
            case " ":
                unitCount += 2
            case "~":
                unitCount += 1
            default:
                break
            }
        }

        let trueLength = max(0, unitCount * samplesPerUnit + rampLength)
        let blockAlignedLength = max(blockSize, blockSize * Int(ceil(Double(max(trueLength, 1)) / Double(blockSize))))
        var result = Array(repeating: Float(0), count: blockAlignedLength)
        var position = 0

        func addRampOn() {
            guard !rampOn.isEmpty else { return }
            let end = min(position + rampOn.count, result.count)
            for index in position..<end {
                result[index] = rampOn[index - position]
            }
            position = end
        }

        func addRampOff() {
            guard !rampOff.isEmpty else { return }
            let end = min(position + rampOff.count, result.count)
            for index in position..<end {
                result[index] = rampOff[index - position]
            }
            position = end
        }

        func addOn(duration: Int) {
            let count = max(0, duration * samplesPerUnit - rampLength)
            guard count > 0 else { return }
            let end = min(position + count, result.count)
            for index in position..<end {
                result[index] = 1
            }
            position = end
        }

        func addOff(duration: Int) {
            let count = max(0, duration * samplesPerUnit - rampLength)
            position = min(result.count, position + count)
        }

        for character in morseMessage {
            switch character {
            case ".":
                addRampOn()
                addOn(duration: 1)
                addRampOff()
                addOff(duration: 1)
            case "-":
                addRampOn()
                addOn(duration: 3)
                addRampOff()
                addOff(duration: 1)
            case " ":
                addOff(duration: 2)
            case "~":
                addOff(duration: 1)
            default:
                break
            }
        }

        if amplitude != 1 {
            for index in result.indices {
                result[index] *= amplitude
            }
        }
        return result
    }

    private func blackmanHarrisKernel(_ x: Float) -> Float {
        let a0: Float = 0.35875
        let a1: Float = 0.48829
        let a2: Float = 0.14128
        let a3: Float = 0.01168
        return a0 - a1 * cos(twoPi * x) + a2 * cos(4 * .pi * x) - a3 * cos(6 * .pi * x)
    }

    private func blackmanHarrisStepResponse(length: Int) -> [Float] {
        guard length > 0 else { return [] }
        var response = Array(repeating: Float(0), count: length)
        for index in response.indices {
            response[index] = blackmanHarrisKernel(Float(index) / Float(length))
        }
        for index in 1..<response.count {
            response[index] += response[index - 1]
        }
        let scale = 1 / max(response.last ?? 1, 1e-6)
        for index in response.indices {
            response[index] *= scale
        }
        return response
    }

    private func makeRamp() {
        rampLength = max(1, Int(round(2.7 * Double(riseTime) * Double(rate))))
        rampOn = blackmanHarrisStepResponse(length: rampLength)
        rampOff = Array(repeating: 0, count: rampLength)
        for index in 0..<rampLength {
            rampOff[rampLength - 1 - index] = rampOn[index]
        }
    }
}

final class QuickAverage {
    var passes: Int {
        didSet {
            passes = clamp(passes, lower: 1, upper: 8)
            reset()
        }
    }

    var points: Int {
        didSet {
            points = max(1, points)
            reset()
        }
    }

    private var scale: Float = 1
    private var reBuffers: [[Double]] = []
    private var imBuffers: [[Double]] = []
    private var index = 0
    private var previousIndex = 0

    init(passes: Int = 4, points: Int = 128) {
        self.passes = passes
        self.points = points
        reset()
    }

    func reset() {
        reBuffers = Array(repeating: Array(repeating: 0, count: points), count: passes + 1)
        imBuffers = Array(repeating: Array(repeating: 0, count: points), count: passes + 1)
        scale = pow(Float(points), Float(-passes))
        index = 0
        previousIndex = points - 1
    }

    func filter(_ value: Float) -> Float {
        let result = doFilter(value, buffers: &reBuffers)
        previousIndex = index
        index = (index + 1) % points
        return result
    }

    func filter(_ re: Float, _ im: Float) -> ComplexSample {
        let filtered = ComplexSample(re: doFilter(re, buffers: &reBuffers), im: doFilter(im, buffers: &imBuffers))
        previousIndex = index
        index = (index + 1) % points
        return filtered
    }

    private func doFilter(_ value: Float, buffers: inout [[Double]]) -> Float {
        var result = Double(value)
        for passIndex in 1...passes {
            let current = result
            result = buffers[passIndex][previousIndex] - buffers[passIndex - 1][index] + current
            buffers[passIndex - 1][index] = current
        }
        buffers[passes][index] = result
        return Float(result) * scale
    }
}

final class MovingAverage {
    var points: Int {
        didSet { points = max(1, points); reset() }
    }

    var passes: Int {
        didSet { passes = max(1, passes); reset() }
    }

    var samplesInInput: Int {
        didSet { samplesInInput = max(1, samplesInInput); reset() }
    }

    var decimateFactor: Int {
        didSet { decimateFactor = max(1, decimateFactor); reset() }
    }

    var gainDb: Float {
        didSet { calculateScale() }
    }

    private var realBuffers: [[Float]] = []
    private var imagBuffers: [[Float]] = []
    private var norm: Float = 1

    init(points: Int = 129, passes: Int = 3, samplesInInput: Int = 512, decimateFactor: Int = 1, gainDb: Float = 0) {
        self.points = points
        self.passes = passes
        self.samplesInInput = samplesInInput
        self.decimateFactor = decimateFactor
        self.gainDb = gainDb
        reset()
    }

    func reset() {
        realBuffers = Array(repeating: Array(repeating: 0, count: samplesInInput + points), count: passes + 1)
        imagBuffers = Array(repeating: Array(repeating: 0, count: samplesInInput + points), count: passes + 1)
        calculateScale()
    }

    func filter(_ data: [Float]) -> [Float] {
        var result: [Float] = []
        filter(data, into: &result)
        return result
    }

    func filter(_ data: ComplexBuffer) -> ComplexBuffer {
        var result = ComplexBuffer(count: outputCount)
        filter(data, into: &result)
        return result
    }

    func filter(_ data: [Float], into result: inout [Float]) {
        filter(data, into: &result, buffers: &realBuffers)
    }

    func filter(_ data: ComplexBuffer, into result: inout ComplexBuffer) {
        result.resizeIfNeeded(count: outputCount)
        filter(data.re, into: &result.re, buffers: &realBuffers)
        filter(data.im, into: &result.im, buffers: &imagBuffers)
    }

    private func calculateScale() {
        norm = pow(10, 0.05 * gainDb) * pow(Float(points), Float(-passes))
    }

    private var outputCount: Int {
        max(1, samplesInInput / max(1, decimateFactor))
    }

    private func filter(_ data: [Float], into result: inout [Float], buffers: inout [[Float]]) {
        pushArray(data, into: &buffers[0])
        for passIndex in 1...passes {
            pass(buffers[passIndex - 1], into: &buffers[passIndex])
        }
        writeResult(from: buffers[passes], into: &result)
    }

    private func pushArray(_ source: [Float], into destination: inout [Float]) {
        let count = source.count
        let offset = destination.count - count
        if offset > 0 {
            for index in 0..<offset {
                destination[index] = destination[index + count]
            }
        }
        for index in 0..<count {
            destination[offset + index] = source[index]
        }
    }

    private func shiftArray(_ buffer: inout [Float], count: Int) {
        guard count > 0, count < buffer.count else { return }
        let remaining = buffer.count - count
        for index in 0..<remaining {
            buffer[index] = buffer[index + count]
        }
    }

    private func pass(_ source: [Float], into destination: inout [Float]) {
        shiftArray(&destination, count: samplesInInput)
        guard points < source.count else { return }
        for index in points..<source.count {
            destination[index] = destination[index - 1] - source[index - points] + source[index]
        }
    }

    private func writeResult(from source: [Float], into result: inout [Float]) {
        ensureFloatBuffer(&result, count: outputCount)
        if decimateFactor == 1 {
            for index in 0..<samplesInInput {
                result[index] = source[points + index] * norm
            }
            return
        }
        for index in 0..<outputCount {
            result[index] = source[points + index * decimateFactor] * norm
        }
    }
}

final class VolumeControl {
    var maxOut: Float = 20_000 {
        didSet { calculateBeta() }
    }

    var noiseInDb: Float {
        get { 20 * log10(noiseIn) }
        set {
            noiseIn = pow(10, 0.05 * newValue)
            calculateBeta()
        }
    }

    var noiseOutDb: Float {
        get { 20 * log10(noiseOut) }
        set {
            noiseOut = min(0.25 * maxOut, pow(10, 0.05 * newValue))
            calculateBeta()
        }
    }

    var attackSamples: Int = 28 {
        didSet {
            attackSamples = max(1, attackSamples)
            makeAttackShape()
        }
    }

    var holdSamples: Int = 28 {
        didSet {
            holdSamples = max(1, holdSamples)
            makeAttackShape()
        }
    }

    var agcEnabled: Bool = false {
        didSet {
            if agcEnabled && !oldValue {
                reset()
            }
        }
    }

    private var noiseIn: Float = 1
    private var noiseOut: Float = 2_000
    private var beta: Float = 1
    private var defaultGain: Float = 1
    private var envelope: Float = 0
    private var holdCounter = 0
    private var releaseAlpha: Float = 0

    init() {
        calculateBeta()
        updateDynamics()
    }

    func reset() {
        envelope = 0
        holdCounter = 0
    }

    func process(_ data: [Float]) -> [Float] {
        var result = data
        process(&result)
        return result
    }

    func process(_ data: inout [Float]) {
        if !agcEnabled {
            for index in data.indices {
                data[index] = applyDefaultGain(data[index])
            }
            return
        }
        for index in data.indices {
            data[index] = applyAgc(data[index])
        }
    }

    private func makeAttackShape() {
        updateDynamics()
    }

    private func calculateBeta() {
        beta = noiseIn / log(maxOut / max(maxOut - noiseOut, 1))
        defaultGain = noiseOut / noiseIn
    }

    private func applyAgc(_ value: Float) -> Float {
        let magnitude = abs(value)
        if magnitude >= envelope {
            envelope = magnitude
            holdCounter = holdSamples
        } else if holdCounter > 0 {
            holdCounter -= 1
        } else {
            envelope = releaseAlpha * envelope + (1 - releaseAlpha) * magnitude
        }
        let denominator = max(max(envelope, noiseIn), Float(1))
        let gain = min(defaultGain, maxOut / denominator)
        return clamp(value * gain, lower: -maxOut, upper: maxOut)
    }

    private func applyDefaultGain(_ value: Float) -> Float {
        clamp(value * defaultGain, lower: -maxOut, upper: maxOut)
    }

    private func updateDynamics() {
        let releaseWindow = max(1, attackSamples + holdSamples)
        releaseAlpha = exp(-1 / Float(releaseWindow))
        reset()
    }
}

final class Modulator {
    var samplesPerSecond: Int = Int(defaultSampleRate) {
        didSet { calculateTables() }
    }

    var carrierFrequency: Float = 600 {
        didSet { calculateTables() }
    }

    var gain: Float = 1 {
        didSet { calculateTables() }
    }

    private var sine: [Float] = []
    private var cosine: [Float] = []
    private var sampleNumber = 0

    init() {
        calculateTables()
    }

    func modulate(_ data: ComplexBuffer) -> [Float] {
        var result: [Float] = []
        modulate(data, into: &result)
        return result
    }

    func modulate(_ data: ComplexBuffer, into result: inout [Float]) {
        ensureFloatBuffer(&result, count: data.re.count)
        guard !cosine.isEmpty else {
            for index in data.re.indices {
                result[index] = data.re[index]
            }
            return
        }
        for index in result.indices {
            result[index] = data.re[index] * sine[sampleNumber] - data.im[index] * cosine[sampleNumber]
            sampleNumber = (sampleNumber + 1) % cosine.count
        }
    }

    private func calculateTables() {
        let count = max(1, Int(round(Float(samplesPerSecond) / max(carrierFrequency, 1))))
        let delta = twoPi / Float(count)
        sine = Array(repeating: 0, count: count)
        cosine = Array(repeating: 0, count: count)
        for index in 0..<count {
            sine[index] = sin(delta * Float(index)) * gain
            cosine[index] = cos(delta * Float(index)) * gain
        }
        sampleNumber = 0
    }
}

final class QSBEffect {
    var bandwidth: Float {
        didSet { setBandwidth(bandwidth) }
    }

    var qsbLevel: Float = 1

    private let filter = QuickAverage(passes: 3, points: 32)
    private let bufferSize: Int
    private var random = FastRandom(seed: 0x6A09_E667_F3BC_C909)
    private var gain: Float = 1

    init(bufferSize: Int, bandwidth: Float = 0.1) {
        self.bufferSize = bufferSize
        self.bandwidth = bandwidth
        setBandwidth(bandwidth)
    }

    func apply(to array: inout [Float]) {
        let blockCount = max(1, array.count / max(1, bufferSize / 4))
        let miniBlock = max(1, bufferSize / 4)
        for block in 0..<blockCount {
            let nextGain = newGain()
            let delta = (nextGain - gain) / Float(miniBlock)
            for index in 0..<miniBlock {
                let sampleIndex = block * miniBlock + index
                guard sampleIndex < array.count else { continue }
                array[sampleIndex] *= gain
                gain += delta
            }
        }
    }

    private func newGain() -> Float {
        let sample = filter.filter(random.nextSignedFloat(), random.nextSignedFloat())
        let value = sqrt((sample.re * sample.re + sample.im * sample.im) * 3 * Float(filter.points))
        return value * qsbLevel + (1 - qsbLevel)
    }

    private func setBandwidth(_ value: Float) {
        let points = Int(ceil(0.37 * defaultSampleRate / Double(max(1, bufferSize / 4)) / Double(max(value, 0.01))))
        filter.points = max(1, points)
        gain = 1
        for _ in 0..<(filter.points * 3) {
            gain = newGain()
        }
    }
}
