/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Main source file for SignalGenerator.
*/

import Foundation
import AVFoundation

let userDefaults = UserDefaults.standard

struct OptionNames {
    static let signal = "signal"
    static let frequency = "freq"
    static let duration = "duration"
    static let output = "output"
    static let amplitude = "amplitude"
}

if CommandLine.arguments.contains("-help") || CommandLine.arguments.contains("-h") {
    print("SignalGenerator\n")
    print("Usage:    SignalGenerator [-signal SIGNAL] [-freq FREQUENCY] [-duration DURATION] [-output FILEPATH] [-amplitude VALUE]\n")
    print("Options:\n")
    print("-\(OptionNames.signal)       Type of signal: sine (default), square, sawtooth, triangle and noise")
    print("-\(OptionNames.frequency)    Frequncy in Hertz (defaut: 440)")
    print("-\(OptionNames.duration)     Duration in seconds (default: 5.0)")
    print("-\(OptionNames.amplitude)    Amplitude between 0.0 and 1.0 (default: 0.5)")
    print("-\(OptionNames.output)       Path to output file. If not set, no output file is written")
    print("-help or -h   Show this help\n")
    exit(0)
}

let getFloatForKeyOrDefault = { (key: String, defaultValue: Float) -> Float in
    let value = userDefaults.float(forKey: key)
    return value > 0.0 ? value : defaultValue
}

let frequency = getFloatForKeyOrDefault(OptionNames.frequency, 440)
let amplitude = min(max(getFloatForKeyOrDefault(OptionNames.amplitude, 0.5), 0.0), 1.0)
let duration = getFloatForKeyOrDefault(OptionNames.duration, 5.0)
let outputPath = userDefaults.string(forKey: OptionNames.output)

let sine = { (time: Float) -> Float in
    return amplitude * sin(2.0 * Float.pi * frequency * time)
}

let whiteNoise = { (time: Float) -> Float in
    return amplitude * ((Float(arc4random_uniform(UINT32_MAX)) / Float(UINT32_MAX)) * 2 - 1)
}

let sawtooth = { (time: Float) -> Float in
    let period = 1.0 / frequency
    let currentTime = fmod(Double(time), Double(period))
    return amplitude * ((Float(currentTime) / period) * 2 - 1.0)
}

let square = { (time: Float) -> Float in
    let period: Double = 1.0 / Double(frequency)
    let currentTime = fmod(Double(time), period)

    return currentTime < (period / 2.0) ? amplitude : -1.0 * amplitude
}

let triangle = { (time: Float) -> Float in
    let period = 1.0 / Double(frequency)
    let currentTime = fmod(Double(time), period)

    let value = currentTime / period

    var result = 0.0
    if value < 0.25 {
        result = value * 4
    } else if value < 0.75 {
        result = 2.0 - (value * 4.0)
    } else {
        result = value * 4 - 4.0
    }

    return amplitude * Float(result)
}

var signal: (Float) -> Float
switch userDefaults.string(forKey: OptionNames.signal) {
case "noise":
    signal = whiteNoise
case "square":
    signal = square
case "sawtooth":
    signal = sawtooth
case "triangle":
    signal = triangle
default:
    signal = sine
}

let engine = AVAudioEngine()
let mainMixer = engine.mainMixerNode
let output = engine.outputNode
let format = output.inputFormat(forBus: 0)
let sampleRate = format.sampleRate
// Use output format for input but reduce channel count to 1
let inputFormat = AVAudioFormat(commonFormat: format.commonFormat,
                                sampleRate: format.sampleRate,
                                channels: 1,
                                interleaved: format.isInterleaved)

// The time interval by which we advance each frame.
let deltaTime = 1.0 / Float(sampleRate)
var time: Float = 0

let srcNode = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
    let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
    for frame in 0..<Int(frameCount) {
        // Get signal value for this frame at time.
        let value = signal(time)
        // Advance the time for the next frame.
        time += deltaTime
        // Set the same value on all channels (due to the inputFormat we have only 1 channel though).
        for buffer in ablPointer {
            let buf: UnsafeMutableBufferPointer<Float> = UnsafeMutableBufferPointer(buffer)
            buf[frame] = value
        }
    }
    return noErr
}

engine.attach(srcNode)

engine.connect(srcNode, to: mainMixer, format: inputFormat)
engine.connect(mainMixer, to: output, format: nil)
mainMixer.outputVolume = 0.5

var outFile: AVAudioFile?
if let path = outputPath {
    var samplesWritten: AVAudioFrameCount = 0
    let outUrl = URL(fileURLWithPath: path).standardizedFileURL
    let outDirExists = try? outUrl.deletingLastPathComponent().checkResourceIsReachable()
    if outDirExists != nil {
		var outputFormatSettings = srcNode.outputFormat(forBus: 0).settings
		// Audio files have to be interleaved.
		outputFormatSettings[AVLinearPCMIsNonInterleaved] = false
        outFile = try? AVAudioFile(forWriting: outUrl, settings: outputFormatSettings)
        // Calculate the total number of samples to write for the duration.
        let samplesToWrite = AVAudioFrameCount(duration * Float(sampleRate))
        srcNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { buffer, _ in
            // Check if we need to adjust the buffer frame length to match
            // the requested number of samples.
            if samplesWritten + buffer.frameLength > samplesToWrite {
                buffer.frameLength = samplesToWrite - samplesWritten
            }
            do {
                try outFile?.write(from: buffer)
            } catch {
                print("Error writing file \(error)")
            }
            samplesWritten += buffer.frameLength

            // Exit the app if we have written the requested number of samples.
            if samplesWritten >= samplesToWrite {
                CFRunLoopStop(CFRunLoopGetMain())
            }
        }
    }
}

do {
    try engine.start()

	// When writing the output file, the run loop will be stopped from the tap block
	// after the number of samples for the requested duration are written.
	// Otherwise, the run duration of the run loop is specified when started.
    if outFile != nil {
		CFRunLoopRun()
    } else {
		CFRunLoopRunInMode(.defaultMode, CFTimeInterval(duration), false)
    }
} catch {
    print("Could not start engine: \(error)")
}
