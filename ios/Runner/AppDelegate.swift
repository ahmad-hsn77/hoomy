import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var messageChimePlayer: AVAudioPlayer?
  private var messageReceivePlayer: AVAudioPlayer?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let launched = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    configureAudioChannel()
    return launched
  }

  private func configureAudioChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      return
    }

    let channel = FlutterMethodChannel(
      name: "hoomy/audio",
      binaryMessenger: controller.binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      if call.method == "playMessageChime" {
        self?.playMessageChime()
        result(nil)
      } else if call.method == "playMessageReceiveChime" {
        self?.playMessageReceiveChime()
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func playMessageChime() {
    guard let url = Bundle.main.url(forResource: "message_chime", withExtension: "wav") else {
      return
    }

    do {
      try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
      messageChimePlayer = try AVAudioPlayer(contentsOf: url)
      messageChimePlayer?.volume = 0.34
      messageChimePlayer?.prepareToPlay()
      messageChimePlayer?.play()
    } catch {
      // Keep message sending non-blocking if the optional cue cannot play.
    }
  }

  private func playMessageReceiveChime() {
    guard let url = Bundle.main.url(forResource: "message_receive", withExtension: "wav") else {
      return
    }

    do {
      try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
      messageReceivePlayer = try AVAudioPlayer(contentsOf: url)
      messageReceivePlayer?.volume = 0.38
      messageReceivePlayer?.prepareToPlay()
      messageReceivePlayer?.play()
    } catch {
      // Keep receiving messages non-blocking if the optional cue cannot play.
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
