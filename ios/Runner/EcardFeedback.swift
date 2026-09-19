import AVFoundation
import CoreHaptics
import Flutter
import UIKit

/// Plays the waveforms the Dart layer names (lib/utils/haptics.dart).
///
/// Core Haptics gives the phone the whole pattern in one timeline, and the
/// fallback on devices without an engine (and in the simulator) still fires one
/// generator per pulse at the requested intensity. Either way the phone is told
/// what to play rather than asked to decide, so one action feels the same on
/// every device — including the durations, which is where a platform default
/// hurts: a motor held on for a quarter of a second reads as an alarm.
final class EcardFeedback {
  private struct Pulse {
    let atMs: Double
    let durationMs: Double
    let intensity: Float
    let sharpness: Float
  }

  private struct Request {
    let id: String
    let pulses: [Pulse]
    let soundAsset: String?
    let sound: Bool
    let vibration: Bool
    /// How long the sound runs; the session stays alive for this long.
    let windowMs: Double
  }

  private enum Failure: Error { case missingAsset, audioUnavailable }
  private let registrar: FlutterPluginRegistrar
  private let channel: FlutterMethodChannel
  private var engine: CHHapticEngine?
  private var resources: [String: CHHapticAudioResourceID] = [:]
  private var hapticPlayer: CHHapticPatternPlayer?
  private var audioPlayer: AVAudioPlayer?
  private var work: [DispatchWorkItem] = []
  private var generation = 0

  init(registrar: FlutterPluginRegistrar) {
    self.registrar = registrar
    channel = FlutterMethodChannel(name: "techpie/feedback", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "play" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let self, let args = call.arguments as? [String: Any],
            let request = Self.request(args) else {
        result(nil)
        return
      }
      do {
        try self.play(request)
        result(nil)
      } catch {
        self.stopPlayback()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        result(FlutterError(code: "feedback_failed", message: "Feedback could not be played.", details: nil))
      }
    }
  }

  private static func request(_ args: [String: Any]) -> Request? {
    let pulses = ((args["pulses"] as? [[String: Any]]) ?? []).map { entry in
      Pulse(
        atMs: (entry["atMs"] as? NSNumber)?.doubleValue ?? 0,
        durationMs: (entry["durationMs"] as? NSNumber)?.doubleValue ?? 0,
        intensity: Float((entry["intensity"] as? NSNumber)?.doubleValue ?? 1),
        sharpness: Float((entry["sharpness"] as? NSNumber)?.doubleValue ?? 0.5)
      )
    }
    let soundAsset = args["soundAsset"] as? String
    let sound = args["sound"] as? Bool == true && soundAsset != nil
    if pulses.isEmpty && !sound { return nil }
    let declared = (args["soundDurationMs"] as? NSNumber)?.doubleValue ?? 0
    let vibrated = pulses.map { $0.atMs + $0.durationMs }.max() ?? 0
    return Request(
      id: args["id"] as? String ?? "waveform",
      pulses: pulses,
      soundAsset: soundAsset,
      sound: sound,
      vibration: args["vibration"] as? Bool == true,
      windowMs: max(declared, vibrated)
    )
  }

  private func assetURL(_ asset: String) throws -> URL {
    let key = registrar.lookupKey(forAsset: asset)
    guard let path = Bundle.main.path(forResource: key, ofType: nil) else { throw Failure.missingAsset }
    return URL(fileURLWithPath: path)
  }

  private func play(_ request: Request) throws {
    guard request.sound || request.vibration else { return }
    generation += 1
    let current = generation
    stopPlayback()
    let session = AVAudioSession.sharedInstance()
    if request.sound {
      try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
      try session.setActive(true)
    }
    if request.vibration && CHHapticEngine.capabilitiesForHardware().supportsHaptics {
      do {
        try playSynchronized(request, session: session)
      } catch {
        // Keep audio usable after an engine interruption or on older devices.
        try playFallback(request, generation: current)
      }
    } else {
      // iOS simulators and iPads may provide audio without a haptic engine.
      try playFallback(request, generation: current)
    }
    #if DEBUG
    NSLog("TechPieFeedback play %@ sound=%d vibration=%d",
          request.id, request.sound ? 1 : 0, request.vibration ? 1 : 0)
    #endif
    let cleanup = DispatchWorkItem { [weak self] in
      guard let self, self.generation == current else { return }
      self.stopPlayback()
      try? session.setActive(false, options: [.notifyOthersOnDeactivation])
    }
    work.append(cleanup)
    DispatchQueue.main.asyncAfter(deadline: .now() + request.windowMs / 1000 + 0.04, execute: cleanup)
  }

  private func playSynchronized(_ request: Request, session: AVAudioSession) throws {
    if engine == nil {
      let created = try CHHapticEngine(audioSession: session)
      created.isAutoShutdownEnabled = true
      created.resetHandler = { [weak self] in
        DispatchQueue.main.async { self?.resources.removeAll() }
      }
      engine = created
    }
    guard let engine else { throw Failure.audioUnavailable }
    try engine.start()
    var events: [CHHapticEvent] = []
    if request.sound, let asset = request.soundAsset {
      let resource: CHHapticAudioResourceID
      if let cached = resources[asset] {
        resource = cached
      } else {
        if #available(iOS 15.0, *) {
          resource = try engine.registerAudioResource(assetURL(asset), options: [CHHapticAudioResourceKeyUseVolumeEnvelope: false])
        } else {
          resource = try engine.registerAudioResource(assetURL(asset), options: [:])
        }
        resources[asset] = resource
      }
      events.append(CHHapticEvent(audioResourceID: resource,
        parameters: [CHHapticEventParameter(parameterID: .audioVolume, value: 1)], relativeTime: 0))
    }
    if request.vibration {
      events.append(contentsOf: request.pulses.map { pulse in
        CHHapticEvent(eventType: .hapticTransient, parameters: [
          CHHapticEventParameter(parameterID: .hapticIntensity, value: pulse.intensity),
          CHHapticEventParameter(parameterID: .hapticSharpness, value: pulse.sharpness),
        ], relativeTime: pulse.atMs / 1000)
      })
    }
    let player = try engine.makePlayer(with: CHHapticPattern(events: events, parameters: []))
    hapticPlayer = player
    try player.start(atTime: CHHapticTimeImmediate)
  }

  private func playFallback(_ request: Request, generation: Int) throws {
    let lead = 0.02
    if request.sound, let asset = request.soundAsset {
      var playing = false
      if let player = try? AVAudioPlayer(contentsOf: assetURL(asset)),
         player.prepareToPlay(), player.play(atTime: player.deviceCurrentTime + lead) {
        audioPlayer = player
        playing = true
      }
      if !playing {
        // The waveform is the point: a sound that will not play must not take
        // the vibration down with it, nor fail the action that asked for it.
        if !request.vibration { throw Failure.audioUnavailable }
        NSLog("TechPieFeedback: sound unavailable for %@; vibrating only", request.id)
      }
    }
    guard request.vibration else { return }
    for pulse in request.pulses {
      let generator = UIImpactFeedbackGenerator(style: .heavy)
      generator.prepare()
      let item = DispatchWorkItem { [weak self] in
        guard self?.generation == generation else { return }
        generator.impactOccurred(intensity: CGFloat(pulse.intensity))
      }
      work.append(item)
      DispatchQueue.main.asyncAfter(deadline: .now() + lead + pulse.atMs / 1000, execute: item)
    }
  }

  private func stopPlayback() {
    work.forEach { $0.cancel() }
    work.removeAll()
    try? hapticPlayer?.stop(atTime: CHHapticTimeImmediate)
    hapticPlayer = nil
    audioPlayer?.stop()
    audioPlayer = nil
  }
}
