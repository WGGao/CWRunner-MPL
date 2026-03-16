// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Modifications for iOS / Swift adaptation by WGGao (BA3QT).
import Foundation

enum RunMode: String, CaseIterable, Identifiable, Codable {
    case stop
    case pileup
    case single
    case wpx
    case hst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stop:
            return "Stopped"
        case .pileup:
            return "Pile-Up"
        case .single:
            return "Single Calls"
        case .wpx:
            return "WPX"
        case .hst:
            return "HST"
        }
    }
}

enum StationMessage: CaseIterable, Hashable {
    case none
    case cq
    case nr
    case tu
    case myCall
    case hisCall
    case b4
    case question
    case nilReport
    case garbage
    case rNr
    case rNr2
    case deMyCall1
    case deMyCall2
    case deMyCallNr1
    case deMyCallNr2
    case nrQuestion
    case longCQ
    case myCallNr2
    case qrl
    case qrl2
    case qsy
    case agn

    var title: String {
        switch self {
        case .cq: return "CQ"
        case .nr: return "#"
        case .tu: return "TU"
        case .myCall: return "My Call"
        case .hisCall: return "His Call"
        case .b4: return "B4"
        case .question: return "?"
        case .agn: return "AGN"
        default: return ""
        }
    }
}

enum StationState {
    case listening
    case copying
    case preparingToSend
    case sending
}

enum StationEvent {
    case timeout
    case messageSent
    case meStarted
    case meFinished
}

enum OperatorState {
    case needPrevEnd
    case needQso
    case needNr
    case needCall
    case needCallNr
    case needEnd
    case done
    case failed
}

enum CallCheckResult {
    case no
    case yes
    case almost
}

struct ContestConfiguration: Equatable, Codable {
    var call = "BA3QT"
    var operatorName = ""
    var wpm = 30
    var bandwidth = 500
    var pitch = 600
    var qsk = true
    var rit = 0
    var bufferSize = 512
    var activity = 2
    var qrn = true
    var qrm = true
    var qsb = true
    var flutter = true
    var lids = true
    var duration = 30
}

struct QSORecord: Identifiable, Equatable {
    let id = UUID()
    let timeDays: Double
    let call: String
    let rst: Int
    let nr: Int
    let sentRST: Int
    let sentNR: Int
    let prefix: String
    let duplicate: Bool
    var wpm: Int = 0
    var trueCall: String = ""
    var trueRST: Int = 0
    var trueNR: Int = 0
    var error: String = "   "

    var timeText: String {
        let seconds = Int(round(timeDays * 24 * 60 * 60))
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    var statusText: String {
        let trimmed = error.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "OK" : trimmed
    }

    var checkText: String {
        let value = trueNR > 0 ? trueNR : nr
        return value > 0 ? String(format: "%03d", value) : "--"
    }
}

struct ScoreSummary: Equatable {
    var rawPoints = 0
    var rawMultipliers = 0
    var rawScore = 0
    var verifiedPoints = 0
    var verifiedMultipliers = 0
    var verifiedScore = 0
    var usesCallScore = false
}

struct MinuteScore: Equatable {
    let minute: Int
    let good: Int
    let bad: Int
    let reached: Bool
}

struct ContestSnapshot {
    let configuration: ContestConfiguration
    let runMode: RunMode
    let elapsedSeconds: Int
    let elapsedText: String
    let rateText: String
    let modeText: String
    let dxCount: Int
    let logs: [QSORecord]
    let score: ScoreSummary
    let minuteScores: [MinuteScore]
}

final class CallsignLibrary {
    private(set) var calls: [String] = CallsignLibrary.makePool()

    func reset() {
        calls = CallsignLibrary.makePool()
    }

    func pick(runMode: RunMode) -> String {
        if calls.isEmpty {
            reset()
        }
        let index = Int.random(in: 0..<calls.count)
        let call = calls[index]
        if runMode == .hst {
            calls.remove(at: index)
        }
        return call
    }

    private static func makePool() -> [String] {
        let prefixes = [
            "K1", "K4", "K9", "N0", "N4", "W6", "W7", "VE3", "VA2", "DL1",
            "F5", "G3", "M0", "PA3", "OK1", "OM2", "SP9", "SM5", "OH2", "I2",
            "EA7", "CT1", "S57", "9A1", "YO9", "LZ1", "HB9", "OE1", "ON4", "UA3",
            "UR5", "JA1", "JA3", "HL2", "BV1", "VR2", "BY1", "DU1", "HS0", "9M2",
            "YB0", "VK3", "ZL2", "ZS6", "PY2", "LU5", "CX1", "A65", "4X6", "UN7"
        ]
        let secondLetters = Array("AEIKLMNPRSTUVWX")
        let thirdLetters = Array("ABCDGHKLMNPRSTUVWXYZ")
        var generated: Set<String> = []

        for prefix in prefixes {
            for index in 0..<72 {
                let a = secondLetters[(index + prefix.count) % secondLetters.count]
                let b = thirdLetters[(index * 3 + prefix.count) % thirdLetters.count]
                let c = thirdLetters[(index * 7 + prefix.count * 2) % thirdLetters.count]
                var call = "\(prefix)\(a)\(b)\(c)"
                if index % 29 == 0 {
                    call += "/P"
                } else if index % 37 == 0 {
                    call += "/QRP"
                }
                generated.insert(call)
            }
        }
        generated.insert("BA3QT")
        return generated.sorted()
    }
}

class Station {
    weak var engine: ContestEngine?

    var amplitude: Float = 0
    var wpm = 30
    var envelope: [Float] = []
    var state: StationState = .listening
    var nr = 1
    var rst = 599
    var myCall = ""
    var hisCall = ""
    var msg: Set<StationMessage> = []
    var msgText = ""
    var sendPosition = 0
    var timeout = -1
    var nrWithError = false
    var isActive = true

    private var bfo: Float = 0
    private var deltaPhase: Float = 0

    var pitch: Int = 0 {
        didSet {
            deltaPhase = twoPi * Float(pitch) / Float(defaultSampleRate)
        }
    }

    func nextBFO() -> Float {
        let result = bfo
        bfo += deltaPhase
        if bfo > twoPi {
            bfo -= twoPi
        } else if bfo < -twoPi {
            bfo += twoPi
        }
        return result
    }

    func currentBFO() -> Float {
        bfo
    }

    func phaseIncrement() -> Float {
        deltaPhase
    }

    func advanceBFO(by sampleCount: Int) {
        guard sampleCount > 0 else { return }
        bfo += Float(sampleCount) * deltaPhase
        while bfo > twoPi {
            bfo -= twoPi
        }
        while bfo < -twoPi {
            bfo += twoPi
        }
    }

    func getBlock(bufferSize: Int, keyer: MorseKeyer) -> [Float] {
        var result: [Float] = []
        fillBlock(bufferSize: bufferSize, keyer: keyer, into: &result)
        return result
    }

    func fillBlock(bufferSize: Int, keyer: MorseKeyer, into result: inout [Float]) {
        ensureFloatBuffer(&result, count: bufferSize)
        for index in result.indices {
            result[index] = 0
        }
        guard !envelope.isEmpty else {
            return
        }
        let end = min(sendPosition + bufferSize, envelope.count)
        let count = end - sendPosition
        if count > 0 {
            for index in 0..<count {
                result[index] = envelope[sendPosition + index]
            }
        }
        sendPosition = min(sendPosition + bufferSize, envelope.count)
        if sendPosition >= envelope.count {
            envelope.removeAll(keepingCapacity: true)
        }
    }

    func processEvent(_ event: StationEvent) {}

    func sendMessage(_ message: StationMessage) {
        if envelope.isEmpty {
            msg.removeAll()
        }
        if message == .none {
            state = .listening
            return
        }
        msg.insert(message)

        switch message {
        case .cq:
            sendText("CQ <my> TEST")
        case .nr:
            sendText("<#>")
        case .tu:
            sendText("TU")
        case .myCall:
            sendText("<my>")
        case .hisCall:
            sendText("<his>")
        case .b4:
            sendText("QSO B4")
        case .question:
            sendText("?")
        case .nilReport:
            sendText("NIL")
        case .rNr:
            sendText("R <#>")
        case .rNr2:
            sendText("R <#> <#>")
        case .deMyCall1:
            sendText("DE <my>")
        case .deMyCall2:
            sendText("DE <my> <my>")
        case .deMyCallNr1:
            sendText("DE <my> <#>")
        case .deMyCallNr2:
            sendText("DE <my> <my> <#>")
        case .nrQuestion:
            sendText("NR?")
        case .longCQ:
            sendText("CQ CQ TEST <my> <my> TEST")
        case .myCallNr2:
            sendText("<my> <my> <#>")
        case .qrl:
            sendText("QRL?")
        case .qrl2:
            sendText("QRL?   QRL?")
        case .qsy:
            sendText("<his>  QSY QSY")
        case .agn:
            sendText("AGN")
        case .garbage, .none:
            break
        }
    }

    func sendText(_ text: String) {
        guard let engine else { return }
        var output = text
        if output.contains("<#>") {
            output = output.replacingOccurrences(of: "<#>", with: nrAsText(), options: [], range: output.range(of: "<#>"))
            output = output.replacingOccurrences(of: "<#>", with: nrAsText())
        }
        output = output.replacingOccurrences(of: "<my>", with: myCall)
        output = output.replacingOccurrences(of: "<his>", with: hisCall)
        msgText = msgText.isEmpty ? output : "\(msgText) \(output)"
        sendMorse(engine.keyer.encode(msgText), keyer: engine.keyer, bufferSize: engine.configuration.bufferSize)
    }

    func sendMorse(_ morse: String, keyer: MorseKeyer, bufferSize: Int) {
        if envelope.isEmpty {
            sendPosition = 0
            bfo = 0
        }
        envelope = keyer.envelope(for: morse, wpm: wpm, amplitude: amplitude, blockSize: bufferSize)
        state = .sending
        timeout = neverTimeout
    }

    func tick() {
        if state == .sending && envelope.isEmpty {
            msgText = ""
            state = .listening
            processEvent(.messageSent)
        } else if state != .sending {
            if timeout > -1 {
                timeout -= 1
            }
            if timeout == 0 {
                processEvent(.timeout)
            }
        }
    }

    func deactivate() {
        isActive = false
    }

    private func nrAsText() -> String {
        var result = String(format: "%d%03d", rst, nr)
        if nrWithError {
            var index = result.index(before: result.endIndex)
            if !"234567".contains(result[index]) && result.count > 1 {
                index = result.index(before: index)
            }
            if "234567".contains(result[index]) {
                let value = Int(String(result[index])) ?? 5
                let adjusted = clamp(value + (Bool.random() ? -1 : 1), lower: 1, upper: 8)
                result.replaceSubrange(index...index, with: "\(adjusted)")
                result += String(format: "EEEEE %03d", nr)
            }
            nrWithError = false
        }

        result = result.replacingOccurrences(of: "599", with: "5NN")
        if engine?.runMode != .hst {
            result = result.replacingOccurrences(of: "000", with: "TTT")
            result = result.replacingOccurrences(of: "00", with: "TT")
            let zeroChance = Float.random(in: 0..<1)
            if zeroChance < 0.4 {
                result = result.replacingOccurrences(of: "0", with: "O")
            } else if zeroChance < 0.97 {
                result = result.replacingOccurrences(of: "0", with: "T")
            }
            if Float.random(in: 0..<1) < 0.97 {
                result = result.replacingOccurrences(of: "9", with: "N")
            }
        }
        return result
    }
}

final class MyStation: Station {
    private var pieces: [String] = []

    func initialize(with configuration: ContestConfiguration) {
        myCall = configuration.call
        nr = 1
        rst = 599
        pitch = configuration.pitch
        wpm = configuration.wpm
        amplitude = 300_000
        msg.removeAll()
        msgText = ""
        pieces.removeAll()
        envelope.removeAll()
        sendPosition = 0
        state = .listening
    }

    override func processEvent(_ event: StationEvent) {
        if event == .messageSent {
            engine?.onMeFinishedSending()
        }
    }

    func abortSend() {
        envelope.removeAll()
        msg = [.garbage]
        msgText = ""
        pieces.removeAll()
        state = .listening
        processEvent(.messageSent)
    }

    override func sendText(_ text: String) {
        addToPieces(text)
        if state != .sending {
            sendNextPiece()
            engine?.onMeStartedSending()
        }
    }

    override func fillBlock(bufferSize: Int, keyer: MorseKeyer, into block: inout [Float]) {
        super.fillBlock(bufferSize: bufferSize, keyer: keyer, into: &block)
        if envelope.isEmpty, !pieces.isEmpty {
            pieces.removeFirst()
            if !pieces.isEmpty {
                sendNextPiece()
            }
            engine?.advanceAfterMessagePiece()
        }
    }

    func updateCallInMessage(_ call: String) -> Bool {
        guard let engine, !call.isEmpty else { return false }
        var updated = false
        if !pieces.isEmpty, pieces[0] == "@" {
            let newEnvelope = engine.keyer.envelope(for: engine.keyer.encode(call), wpm: wpm, amplitude: amplitude, blockSize: engine.configuration.bufferSize)
            updated = newEnvelope.count >= sendPosition
            if updated {
                for index in 0..<sendPosition {
                    if abs(newEnvelope[index] - envelope[index]) > 0.0001 {
                        updated = false
                        break
                    }
                }
            }
            if updated {
                envelope = newEnvelope
                hisCall = call
            }
        }
        if !updated {
            for piece in pieces.dropFirst() where piece == "@" {
                hisCall = call
                return true
            }
        }
        return updated
    }

    private func addToPieces(_ text: String) {
        var remaining = text
        while let range = remaining.range(of: "<his>") {
            let prefix = String(remaining[..<range.lowerBound])
            if !prefix.isEmpty {
                pieces.append(prefix)
            }
            pieces.append("@")
            remaining.removeSubrange(remaining.startIndex..<range.upperBound)
        }
        if !remaining.isEmpty {
            pieces.append(remaining)
        }
    }

    private func sendNextPiece() {
        guard !pieces.isEmpty else { return }
        msgText = ""
        if pieces[0] == "@" {
            super.sendText(hisCall.isEmpty ? " " : hisCall)
        } else {
            super.sendText(pieces[0])
        }
    }
}

final class DXOperator {
    weak var engine: ContestEngine?

    var call = ""
    var skills = 1
    var patience = 5
    var repeatCount = 1
    var state: OperatorState = .needPrevEnd

    func sendDelay() -> Int {
        guard let engine else { return neverTimeout }
        if state == .needPrevEnd {
            return neverTimeout
        }
        if engine.runMode == .hst {
            return RandomTools.secondsToBlocks(0.05 + 0.5 * Float.random(in: 0..<1) * 10 / Float(max(1, wpm())), bufferSize: engine.configuration.bufferSize)
        }
        return RandomTools.secondsToBlocks(0.1 + 0.5 * Float.random(in: 0..<1), bufferSize: engine.configuration.bufferSize)
    }

    func wpm() -> Int {
        guard let engine else { return 30 }
        if engine.runMode == .hst {
            return engine.configuration.wpm
        }
        return Int(round(Float(engine.configuration.wpm) * 0.5 * (1 + Float.random(in: 0..<1))))
    }

    func number() -> Int {
        guard let engine else { return 1 }
        return 1 + Int(round(Float(engine.minute()) * Float(skills)))
    }

    func replyTimeout() -> Int {
        guard let engine else { return 0 }
        let base: Float
        if engine.runMode == .hst {
            base = 60 / Float(max(1, wpm()))
        } else {
            base = Float(6 - skills)
        }
        let raw = Float(RandomTools.secondsToBlocks(base, bufferSize: engine.configuration.bufferSize))
        return Int(round(RandomTools.gaussLimited(mean: raw, limit: raw / 2)))
    }

    func setState(_ newState: OperatorState) {
        guard let engine else { return }
        state = newState
        if newState == .needQso {
            patience = Int(round(RandomTools.rayleigh(mean: 4)))
        } else {
            patience = 5
        }
        if newState == .needQso, !(engine.runMode == .single || engine.runMode == .hst), Float.random(in: 0..<1) < 0.1 {
            repeatCount = 2
        } else {
            repeatCount = 1
        }
    }

    func messageReceived(_ message: Set<StationMessage>) {
        guard let engine else { return }

        if message.contains(.cq) {
            switch state {
            case .needPrevEnd:
                setState(.needQso)
            case .needQso:
                decPatience()
            case .needNr, .needCall, .needCallNr:
                state = .failed
            case .needEnd:
                state = .done
            case .done, .failed:
                break
            }
            return
        }

        if message.contains(.nilReport) {
            switch state {
            case .needPrevEnd:
                setState(.needQso)
            case .needQso:
                decPatience()
            case .needNr, .needCall, .needCallNr, .needEnd:
                state = .failed
            case .done, .failed:
                break
            }
            return
        }

        if message.contains(.hisCall) {
            switch isMyCall() {
            case .yes:
                if state == .needPrevEnd || state == .needQso || state == .needCallNr {
                    setState(.needNr)
                } else if state == .needCall {
                    setState(.needEnd)
                }
            case .almost:
                if state == .needPrevEnd || state == .needQso {
                    setState(.needCallNr)
                } else if state == .needNr {
                    setState(.needCallNr)
                } else if state == .needEnd {
                    setState(.needCall)
                }
            case .no:
                if state == .needQso {
                    state = .needPrevEnd
                } else if state == .needNr || state == .needCall || state == .needCallNr {
                    state = .failed
                } else if state == .needEnd {
                    state = .done
                }
            }
        }

        if message.contains(.b4) {
            switch state {
            case .needPrevEnd, .needQso:
                setState(.needQso)
            case .needNr, .needEnd:
                state = .failed
            case .needCall, .needCallNr, .done, .failed:
                break
            }
        }

        if message.contains(.nr) {
            switch state {
            case .needQso:
                state = .needPrevEnd
            case .needNr:
                if Float.random(in: 0..<1) < 0.9 || engine.runMode == .hst {
                    setState(.needEnd)
                }
            case .needCallNr:
                if Float.random(in: 0..<1) < 0.9 || engine.runMode == .hst {
                    setState(.needCall)
                }
            default:
                break
            }
        }

        if message.contains(.tu), state == .needEnd {
            state = .done
        }

        if !engine.configuration.lids, message == [.garbage] {
            state = .needPrevEnd
        }

        if state != .needPrevEnd {
            decPatience()
        }
    }

    func reply() -> StationMessage {
        guard let engine else { return .none }
        switch state {
        case .needPrevEnd, .done, .failed:
            return .none
        case .needQso:
            return .myCall
        case .needNr:
            return patience == 4 || Float.random(in: 0..<1) < 0.3 ? .nrQuestion : .agn
        case .needCall:
            if engine.runMode == .hst || Float.random(in: 0..<1) > 0.5 {
                return .deMyCallNr1
            }
            return Float.random(in: 0..<1) > 0.25 ? .deMyCallNr2 : .myCallNr2
        case .needCallNr:
            return (engine.runMode == .hst || Float.random(in: 0..<1) > 0.5) ? .deMyCall1 : .deMyCall2
        case .needEnd:
            if patience < 4 {
                return .nr
            }
            return (engine.runMode == .hst || Float.random(in: 0..<1) < 0.9) ? .rNr : .rNr2
        }
    }

    private func decPatience() {
        guard state != .done else { return }
        patience -= 1
        if patience < 1 {
            state = .failed
        }
    }

    private func isMyCall() -> CallCheckResult {
        guard let engine else { return .no }
        let typed = Array(engine.me.hisCall.uppercased())
        let target = Array(call.uppercased())
        let widthX = 2
        let widthY = 2
        let widthD = 2

        var matrix = Array(repeating: Array(repeating: 0, count: target.count + 1), count: typed.count + 1)
        for x in 1...typed.count {
            matrix[x][0] = matrix[x - 1][0] + widthX
        }
        for x in 1...typed.count {
            for y in 1...target.count {
                var top = matrix[x][y - 1]
                if x < typed.count, typed[x - 1] != "?" {
                    top += widthY
                }
                var left = matrix[x - 1][y]
                if typed[x - 1] != "?" {
                    left += widthX
                }
                var diagonal = matrix[x - 1][y - 1]
                if typed[x - 1] != target[y - 1], typed[x - 1] != "?" {
                    diagonal += widthD
                }
                matrix[x][y] = min(top, left, diagonal)
            }
        }

        let penalty = matrix[typed.count][target.count]
        var result: CallCheckResult
        switch penalty {
        case 0:
            result = .yes
        case 1, 2:
            result = .almost
        default:
            result = .no
        }

        if !engine.configuration.lids, typed.count == 2, result == .almost {
            result = .no
        }
        if result == .yes, (typed.count != target.count || typed.contains("?")) {
            result = .almost
        }
        if typed.filter({ $0 != "?" }).count < 2 {
            result = .no
        }
        if engine.configuration.lids, typed.count > 3 {
            switch result {
            case .yes where Float.random(in: 0..<1) < 0.01:
                result = .almost
            case .almost where Float.random(in: 0..<1) < 0.04:
                result = .yes
            default:
                break
            }
        }
        return result
    }
}

final class DXStation: Station {
    let oper = DXOperator()
    private let qsbEffect: QSBEffect

    init(engine: ContestEngine) {
        qsbEffect = QSBEffect(bufferSize: engine.configuration.bufferSize)
        super.init()
        self.engine = engine
        hisCall = engine.configuration.call
        myCall = engine.callsignLibrary.pick(runMode: engine.runMode)
        oper.engine = engine
        oper.call = myCall
        oper.skills = 1 + Int.random(in: 0..<3)
        oper.setState(.needPrevEnd)
        nrWithError = engine.configuration.lids && Float.random(in: 0..<1) < 0.1
        wpm = oper.wpm()
        nr = oper.number()
        rst = engine.configuration.lids && Float.random(in: 0..<1) < 0.03 ? 559 + 10 * Int.random(in: 0..<4) : 599
        qsbEffect.bandwidth = 0.1 + Float.random(in: 0..<0.5)
        if engine.configuration.flutter && Float.random(in: 0..<1) < 0.3 {
            qsbEffect.bandwidth = 3 + Float.random(in: 0..<30)
        }
        amplitude = 9_000 + 18_000 * (1 + RandomTools.uShaped())
        pitch = Int(round(RandomTools.gaussLimited(mean: 0, limit: 300)))
        timeout = neverTimeout
        state = .copying
    }

    override func processEvent(_ event: StationEvent) {
        guard let engine, oper.state != .done else { return }
        switch event {
        case .messageSent:
            timeout = engine.me.state == .sending ? neverTimeout : oper.replyTimeout()
        case .timeout:
            if state == .listening {
                oper.messageReceived([.none])
                if oper.state == .failed {
                    deactivate()
                    return
                }
                state = .preparingToSend
            }
            if state == .preparingToSend {
                for _ in 0..<oper.repeatCount {
                    sendMessage(oper.reply())
                }
            }
        case .meFinished:
            if state != .sending {
                switch state {
                case .copying:
                    oper.messageReceived(engine.me.msg)
                case .listening, .preparingToSend:
                    if engine.me.msg.contains(.cq) || engine.me.msg.contains(.tu) || engine.me.msg.contains(.nilReport) {
                        oper.messageReceived(engine.me.msg)
                    } else {
                        oper.messageReceived([.garbage])
                    }
                case .sending:
                    break
                }

                if oper.state == .failed {
                    deactivate()
                    return
                }
                timeout = oper.sendDelay()
                state = .preparingToSend
            }
        case .meStarted:
            if state != .sending {
                state = .copying
            }
            timeout = neverTimeout
        }
    }

    override func fillBlock(bufferSize: Int, keyer: MorseKeyer, into block: inout [Float]) {
        super.fillBlock(bufferSize: bufferSize, keyer: keyer, into: &block)
        if engine?.configuration.qsb == true {
            qsbEffect.apply(to: &block)
        }
    }

    func writeBack(to record: inout QSORecord) {
        record.trueCall = myCall
        record.trueRST = rst
        record.trueNR = nr
        deactivate()
    }
}

final class QRMStation: Station {
    private var patience = 1

    init(engine: ContestEngine) {
        super.init()
        self.engine = engine
        patience = 1 + Int.random(in: 0..<5)
        myCall = engine.callsignLibrary.pick(runMode: engine.runMode)
        hisCall = engine.configuration.call
        amplitude = 5_000 + 25_000 * Float.random(in: 0..<1)
        pitch = Int(round(RandomTools.gaussLimited(mean: 0, limit: 300)))
        wpm = 30 + Int.random(in: 0..<20)

        switch Int.random(in: 0..<7) {
        case 0:
            sendMessage(.qrl)
        case 1, 2:
            sendMessage(.qrl2)
        case 3, 4, 5:
            sendMessage(.longCQ)
        default:
            sendMessage(.qsy)
        }
    }

    override func processEvent(_ event: StationEvent) {
        switch event {
        case .messageSent:
            patience -= 1
            if patience <= 0 {
                deactivate()
            } else {
                timeout = Int(round(RandomTools.gaussLimited(mean: Float(RandomTools.secondsToBlocks(4, bufferSize: engine?.configuration.bufferSize ?? 512)), limit: 2)))
            }
        case .timeout:
            sendMessage(.longCQ)
        default:
            break
        }
    }
}

final class QRNStation: Station {
    init(engine: ContestEngine) {
        super.init()
        self.engine = engine
        let durationBlocks = max(1, RandomTools.secondsToBlocks(Float.random(in: 0..<1), bufferSize: engine.configuration.bufferSize))
        envelope = Array(repeating: Float(0), count: durationBlocks * engine.configuration.bufferSize)
        amplitude = 100_000 * pow(10, 2 * Float.random(in: 0..<1))
        for index in envelope.indices where Float.random(in: 0..<1) < 0.01 {
            envelope[index] = (Float.random(in: 0..<1) - 0.5) * amplitude
        }
        state = .sending
    }

    override func processEvent(_ event: StationEvent) {
        if event == .messageSent {
            deactivate()
        }
    }
}

final class ContestEngine: InternalSampleProvider {
    // Station callbacks can re-enter the engine while a send/tick is in flight.
    // A recursive lock prevents those legitimate callbacks from deadlocking.
    private let lock = NSRecursiveLock()

    let keyer = MorseKeyer()
    let callsignLibrary = CallsignLibrary()

    private(set) var configuration = ContestConfiguration()
    private(set) var runMode: RunMode = .stop
    private(set) var me = MyStation()
    private var stations: [Station] = []
    private var qsoList: [QSORecord] = []
    private var blockNumber = 0
    private var ritPhase: Float = 0
    private var stopPressed = false
    private var filterA = MovingAverage()
    private var filterB = MovingAverage()
    private var modulator = Modulator()
    private var agc = VolumeControl()
    private var audioRandom = FastRandom(seed: 0x243F_6A88_85A3_08D3)
    private var mixBuffer = ComplexBuffer(count: 0)
    private var filteredBuffer = ComplexBuffer(count: 0)
    private var outputBuffer: [Float] = []
    private var stationBlockBuffer: [Float] = []
    private var silenceBlock: [Float] = []
    private var completionMessage: String?

    var onAdvanceRequested: (() -> Void)?
    var onSessionEnded: ((String?) -> Void)?

    init() {
        me.engine = self
        configure(with: configuration)
        me.initialize(with: configuration)
    }

    func configure(with configuration: ContestConfiguration) {
        withLock {
            self.configuration = configuration
            keyer.rate = Int(defaultSampleRate)
            let filterPoints = max(1, Int(round(0.7 * defaultSampleRate / Double(max(configuration.bandwidth, 1)))))
            let gain = Float(10 * log10(500 / Double(max(configuration.bandwidth, 1))))
            filterA.points = filterPoints
            filterA.passes = 3
            filterA.samplesInInput = configuration.bufferSize
            filterA.gainDb = gain
            filterB.points = filterPoints
            filterB.passes = 3
            filterB.samplesInInput = configuration.bufferSize
            filterB.gainDb = gain
            modulator.samplesPerSecond = Int(defaultSampleRate)
            modulator.carrierFrequency = Float(configuration.pitch)
            agc.noiseInDb = 76
            agc.noiseOutDb = 76
            agc.attackSamples = 155
            agc.holdSamples = 155
            agc.agcEnabled = true
            prepareScratchBuffers(bufferSize: configuration.bufferSize)
            audioRandom = FastRandom(seed: 0x243F_6A88_85A3_08D3 ^ UInt64(configuration.bufferSize) ^ UInt64(configuration.pitch))

            me.myCall = configuration.call
            me.pitch = configuration.pitch
            me.wpm = configuration.wpm
        }
    }

    func start(mode: RunMode) {
        var activeConfiguration = configuration
        if mode == .wpx {
            activeConfiguration.qrn = true
            activeConfiguration.qrm = true
            activeConfiguration.qsb = true
            activeConfiguration.flutter = true
            activeConfiguration.lids = true
        } else if mode == .hst {
            activeConfiguration.qrn = false
            activeConfiguration.qrm = false
            activeConfiguration.qsb = false
            activeConfiguration.flutter = false
            activeConfiguration.lids = false
            activeConfiguration.activity = 4
            activeConfiguration.bandwidth = 600
        }

        configure(with: activeConfiguration)
        withLock {
            runMode = mode
            stopPressed = false
            blockNumber = 0
            ritPhase = 0
            completionMessage = nil
            stations.removeAll()
            qsoList.removeAll()
            callsignLibrary.reset()
            me.initialize(with: activeConfiguration)
            filterA.reset()
            filterB.reset()
            agc.reset()
        }
    }

    func requestStop() {
        withLock {
            stopPressed = true
        }
    }

    func stopNow() -> String? {
        withLock {
            guard runMode != .stop else { return nil }
            stations.removeAll()
            me.abortSend()
            return stopSession()
        }
    }

    func abortMySending() -> Set<StationMessage> {
        withLock {
            let currentMessages = me.msg
            guard me.state == .sending else { return currentMessages }
            me.abortSend()
            return currentMessages
        }
    }

    func sendMessage(_ message: StationMessage, hisCall: String?) {
        withLock {
            if message == .hisCall, let hisCall, !hisCall.isEmpty {
                me.hisCall = hisCall
            }
            me.sendMessage(message)
        }
    }

    func updateCallInOutgoingMessage(_ call: String) -> Bool {
        withLock {
            me.updateCallInMessage(call)
        }
    }

    func setRIT(_ value: Int) {
        withLock {
            configuration.rit = clamp(value, lower: -500, upper: 500)
        }
    }

    func saveQSO(call: String, rst: String, nr: String) -> Bool {
        withLock {
            let cleanedCall = call.replacingOccurrences(of: "?", with: "")
            guard cleanedCall.count >= 3, let rstValue = Int(rst), rst.count == 3, let nrValue = Int(nr), !nr.isEmpty else {
                return false
            }

            let timeDays = RandomTools.blocksToSeconds(Double(blockNumber), bufferSize: configuration.bufferSize) / 86_400
            let prefix = runMode == .hst ? String(callToScore(cleanedCall)) : extractPrefix(cleanedCall)
            let duplicate = qsoList.contains(where: { $0.call == cleanedCall && $0.error == "   " })
            var record = QSORecord(
                timeDays: timeDays,
                call: cleanedCall,
                rst: rstValue,
                nr: nrValue,
                sentRST: me.rst,
                sentNR: me.nr,
                prefix: prefix,
                duplicate: duplicate
            )

            for station in stations.reversed() {
                guard let dxStation = station as? DXStation else { continue }
                if dxStation.oper.state == .done, dxStation.myCall == record.call {
                    dxStation.writeBack(to: &record)
                    break
                }
            }

            checkError(for: &record)
            qsoList.append(record)
            stations.removeAll(where: { !$0.isActive })
            me.nr += 1
            return true
        }
    }

    func snapshot() -> ContestSnapshot {
        withLock {
            let elapsed = RandomTools.blocksToSeconds(Double(blockNumber), bufferSize: configuration.bufferSize)
            let elapsedSeconds = Int(round(elapsed))
            let elapsedText = formatElapsed(seconds: elapsedSeconds)
            let score = scoreSummary()
            let logs = Array(qsoList.suffix(80)).reversed()
            let modeText = runMode == .pileup ? "Pile-Up: \(dxCount())" : runMode.title
            return ContestSnapshot(
                configuration: configuration,
                runMode: runMode,
                elapsedSeconds: elapsedSeconds,
                elapsedText: elapsedText,
                rateText: "\(ratePerHour()) qso/hr",
                modeText: modeText,
                dxCount: dxCount(),
                logs: Array(logs),
                score: score,
                minuteScores: minuteBreakdown(elapsedSeconds: elapsedSeconds)
            )
        }
    }

    func consumeCompletionMessage() -> String? {
        withLock {
            let message = completionMessage
            completionMessage = nil
            return message
        }
    }

    func nextInternalAudioBlock() -> [Float] {
        var endedMessage: String?
        let block = withLock { () -> [Float] in
            guard runMode != .stop else {
                return silenceBlock
            }

            blockNumber += 1
            if blockNumber < 6 {
                return silenceBlock
            }

            let bufferSize = configuration.bufferSize
            let noiseAmplitude: Float = 6_000
            prepareScratchBuffers(bufferSize: bufferSize)
            let ritStep = twoPi * Float(configuration.rit) / Float(defaultSampleRate)

            for index in 0..<bufferSize {
                mixBuffer.re[index] = 1.5 * noiseAmplitude * audioRandom.nextSignedFloat()
                mixBuffer.im[index] = 1.5 * noiseAmplitude * audioRandom.nextSignedFloat()
            }

            if configuration.qrn {
                for index in 0..<bufferSize where audioRandom.nextUnitFloat() < 0.01 {
                    mixBuffer.re[index] = 30 * noiseAmplitude * audioRandom.nextSignedFloat()
                }
                if audioRandom.nextUnitFloat() < 0.01 {
                    addQRN()
                }
            }

            if configuration.qrm, audioRandom.nextUnitFloat() < 0.0002 {
                addQRM()
            }

            for station in stations where station.isActive && station.state == .sending {
                station.fillBlock(bufferSize: bufferSize, keyer: keyer, into: &stationBlockBuffer)
                let phaseStep = station.phaseIncrement() - ritStep
                let startPhase = station.currentBFO() - ritPhase
                let localCosStep = cos(phaseStep)
                let localSinStep = sin(phaseStep)
                var cosPhase = cos(startPhase)
                var sinPhase = sin(startPhase)
                for index in 0..<bufferSize {
                    let sample = stationBlockBuffer[index]
                    mixBuffer.re[index] += sample * cosPhase
                    mixBuffer.im[index] -= sample * sinPhase
                    let nextCos = cosPhase * localCosStep - sinPhase * localSinStep
                    sinPhase = sinPhase * localCosStep + cosPhase * localSinStep
                    cosPhase = nextCos
                }
                station.advanceBFO(by: bufferSize)
            }

            ritPhase += Float(bufferSize) * ritStep
            if ritPhase > twoPi {
                ritPhase -= twoPi
            } else if ritPhase < -twoPi {
                ritPhase += twoPi
            }

            if me.state == .sending {
                me.fillBlock(bufferSize: bufferSize, keyer: keyer, into: &stationBlockBuffer)
                let monitorGain = pow(10, (Float(0.75) - 0.75) * 4)
                var receiveGain: Float = 1
                let amplitude = max(me.amplitude, 1)
                for index in 0..<bufferSize {
                    if configuration.qsk {
                        let candidate = 1 - stationBlockBuffer[index] / amplitude
                        if receiveGain > candidate {
                            receiveGain = candidate
                        } else {
                            receiveGain = receiveGain * 0.997 + 0.003
                        }
                        mixBuffer.re[index] = monitorGain * stationBlockBuffer[index] + receiveGain * mixBuffer.re[index]
                        mixBuffer.im[index] = monitorGain * stationBlockBuffer[index] + receiveGain * mixBuffer.im[index]
                    } else {
                        mixBuffer.re[index] = monitorGain * stationBlockBuffer[index]
                        mixBuffer.im[index] = monitorGain * stationBlockBuffer[index]
                    }
                }
            }

            filterB.filter(mixBuffer, into: &filteredBuffer)
            filterA.filter(filteredBuffer, into: &mixBuffer)
            if blockNumber % 10 == 0 {
                swapFilters()
            }

            modulator.modulate(mixBuffer, into: &outputBuffer)
            agc.process(&outputBuffer)

            me.tick()
            for station in stations where station.isActive {
                station.tick()
            }

            finalizeCompletedStations()

            if runMode == .single, dxCount() == 0 {
                me.msg = [.cq]
                addCaller()?.processEvent(.meFinished)
            } else if runMode == .hst, dxCount() < configuration.activity {
                me.msg = [.cq]
                let missing = configuration.activity - dxCount()
                if missing > 0 {
                    for _ in 0..<missing {
                        addCaller()?.processEvent(.meFinished)
                    }
                }
            }

            if RandomTools.blocksToSeconds(Double(blockNumber), bufferSize: configuration.bufferSize) >= Double(configuration.duration * 60) || stopPressed {
                endedMessage = stopSession()
            }

            stations.removeAll(where: { !$0.isActive })
            return outputBuffer
        }

        if let endedMessage {
            DispatchQueue.main.async { [weak self] in
                self?.onSessionEnded?(endedMessage)
            }
        }
        return block
    }

    func onMeFinishedSending() {
        withLock {
            if !(runMode == .single || runMode == .hst) {
                let justCalledCQ = me.msg.contains(.cq)
                let sentTUPlusCall = !qsoList.isEmpty && me.msg.contains(.tu) && me.msg.contains(.myCall)
                if justCalledCQ || sentTUPlusCall {
                    for _ in 0..<RandomTools.poisson(mean: Float(configuration.activity) / 2) {
                        _ = addCaller()
                    }
                }
            }
            for station in stations where station.isActive {
                station.processEvent(.meFinished)
            }
            stations.removeAll(where: { !$0.isActive })
        }
    }

    func onMeStartedSending() {
        withLock {
            for station in stations where station.isActive {
                station.processEvent(.meStarted)
            }
        }
    }

    func advanceAfterMessagePiece() {
        DispatchQueue.main.async { [weak self] in
            self?.onAdvanceRequested?()
        }
    }

    func minute() -> Double {
        RandomTools.blocksToSeconds(Double(blockNumber), bufferSize: configuration.bufferSize) / 60
    }

    private func addCaller() -> DXStation? {
        guard runMode != .stop else { return nil }
        let station = DXStation(engine: self)
        stations.append(station)
        return station
    }

    private func addQRN() {
        stations.append(QRNStation(engine: self))
    }

    private func addQRM() {
        stations.append(QRMStation(engine: self))
    }

    private func finalizeCompletedStations() {
        guard let lastIndex = qsoList.indices.last else { return }
        for station in stations.reversed() {
            guard let dxStation = station as? DXStation else { continue }
            if dxStation.oper.state == .done, qsoList[lastIndex].call == dxStation.myCall, qsoList[lastIndex].trueCall.isEmpty {
                var updated = qsoList[lastIndex]
                dxStation.writeBack(to: &updated)
                checkError(for: &updated)
                qsoList[lastIndex] = updated
            }
        }
    }

    private func stopSession() -> String? {
        stopPressed = false
        let summary = scoreSummary()
        runMode = .stop
        if summary.usesCallScore {
            completionMessage = "HST score: \(summary.verifiedScore)"
        } else if summary.rawScore > 0 {
            completionMessage = "Verified score: \(summary.verifiedScore) (\(summary.verifiedPoints) QSOs x \(summary.verifiedMultipliers) mults)"
        } else {
            completionMessage = nil
        }
        return completionMessage
    }

    private func minuteBreakdown(elapsedSeconds: Int) -> [MinuteScore] {
        let duration = max(configuration.duration, 1)
        let fullSessionReached = elapsedSeconds >= duration * 60
        let reachedMinutes = fullSessionReached ? duration : min(duration, Int(ceil(Double(elapsedSeconds) / 60)))
        var good = Array(repeating: 0, count: duration)
        var bad = Array(repeating: 0, count: duration)

        for record in qsoList {
            let seconds = max(0, Int(round(record.timeDays * 86_400)))
            let minuteIndex = min(duration - 1, seconds / 60)
            if record.error == "   " {
                good[minuteIndex] += 1
            } else {
                bad[minuteIndex] += 1
            }
        }

        return (0..<duration).map { minute in
            MinuteScore(
                minute: minute,
                good: good[minute],
                bad: bad[minute],
                reached: minute < reachedMinutes
            )
        }
    }

    private func dxCount() -> Int {
        stations.compactMap { $0 as? DXStation }.filter { $0.isActive && $0.oper.state != .done }.count
    }

    private func swapFilters() {
        let currentA = filterA
        filterA = filterB
        filterB = currentA
        filterB.reset()
    }

    private func prepareScratchBuffers(bufferSize: Int) {
        mixBuffer.resizeIfNeeded(count: bufferSize)
        filteredBuffer.resizeIfNeeded(count: bufferSize)
        ensureFloatBuffer(&outputBuffer, count: bufferSize)
        ensureFloatBuffer(&stationBlockBuffer, count: bufferSize)
        ensureFloatBuffer(&silenceBlock, count: bufferSize)
    }

    private func checkError(for record: inout QSORecord) {
        if record.trueCall.isEmpty {
            record.error = "NIL"
        } else if record.duplicate {
            record.error = "DUP"
        } else if record.trueRST != record.rst {
            record.error = "RST"
        } else if record.trueNR != record.nr {
            record.error = "NR "
        } else {
            record.error = "   "
        }
    }

    private func scoreSummary() -> ScoreSummary {
        var summary = ScoreSummary()
        summary.usesCallScore = runMode == .hst

        if summary.usesCallScore {
            summary.rawScore = qsoList.reduce(0) { $0 + callToScore($1.call) }
            summary.verifiedScore = qsoList.filter { $0.error == "   " }.reduce(0) { $0 + callToScore($1.call) }
            summary.rawPoints = summary.rawScore
            summary.verifiedPoints = summary.verifiedScore
            return summary
        }

        summary.rawPoints = qsoList.count
        summary.rawMultipliers = Set(qsoList.map(\.prefix)).count
        summary.rawScore = summary.rawPoints * summary.rawMultipliers

        let cleanQSOs = qsoList.filter { $0.error == "   " }
        summary.verifiedPoints = cleanQSOs.count
        summary.verifiedMultipliers = Set(cleanQSOs.map(\.prefix)).count
        summary.verifiedScore = summary.verifiedPoints * summary.verifiedMultipliers
        return summary
    }

    private func ratePerHour() -> Int {
        let current = RandomTools.blocksToSeconds(Double(blockNumber), bufferSize: configuration.bufferSize) / 86_400
        guard current > 0 else { return 0 }
        let delta = min(5.0 / 1_440.0, current)
        let recent = qsoList.reversed().prefix { $0.timeDays > current - delta }
        return Int(round(Double(recent.count) / delta / 24))
    }

    private func extractPrefix(_ call: String) -> String {
        var cleaned = call + "|"
        cleaned = cleaned.replacingOccurrences(of: "/QRP|", with: "")
        cleaned = cleaned.replacingOccurrences(of: "/MM|", with: "")
        cleaned = cleaned.replacingOccurrences(of: "/M|", with: "")
        cleaned = cleaned.replacingOccurrences(of: "/P|", with: "")
        cleaned = cleaned.replacingOccurrences(of: "|", with: "")
        cleaned = cleaned.replacingOccurrences(of: "//", with: "/")
        guard cleaned.count >= 2 else { return "" }

        var digitOverride = ""
        let parts = cleaned.split(separator: "/")
        var result = cleaned

        if parts.count == 2 {
            let first = String(parts[0])
            let second = String(parts[1])
            if first.count == 1, first.first?.isNumber == true {
                digitOverride = first
                result = second
            } else if second.count == 1, second.first?.isNumber == true {
                digitOverride = second
                result = first
            } else {
                result = first.count <= second.count ? first : second
            }
        }

        if result.contains("/") {
            return ""
        }

        while result.count > 2, let last = result.last, !last.isNumber {
            result.removeLast()
        }

        if let last = result.last, !last.isNumber {
            result += "0"
        }
        if !digitOverride.isEmpty, !result.isEmpty {
            result.removeLast()
            result += digitOverride
        }
        return String(result.prefix(5))
    }

    private func callToScore(_ call: String) -> Int {
        let morse = keyer.encode(call)
        var score = -1
        for character in morse {
            switch character {
            case ".":
                score += 2
            case "-":
                score += 4
            case " ":
                score += 2
            default:
                break
            }
        }
        return score
    }

    private func formatElapsed(seconds: Int) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        return String(format: "%02d:%02d", minutes, secs)
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
