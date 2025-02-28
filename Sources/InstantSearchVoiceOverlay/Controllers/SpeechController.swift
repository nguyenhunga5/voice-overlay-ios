//
//  SpeechController.swift
//  InstantSearch
//
//  Created by Robert Mogos on 23/05/2018.
//

import UIKit
import Speech
import AVFoundation

public typealias SpeechTextHandler = (String, Bool, Any?) -> Void
public typealias SpeechResultScreenHandler = (String) -> Void
public typealias SpeechErrorHandler = (Error?) -> Void

/// A controller object that manages the speech recognition to text
/// `SpeechController` is using the Speech framework, so it can only be used with iOS 10+
/// Simply initilise the controller with the desired `locale` or the device's `default` one
/// let speechController = SpeechController()
/// let speechController = SpeechController(locale: Locale(identifier: "fr_FR"))
/// Do not forget to add `NSSpeechRecognitionUsageDescription` and `NSMicrophoneUsageDescription` to your Info.plist
@available(iOS 10.0, *)
@objc public class SpeechController: NSObject, SFSpeechRecognizerDelegate, Recordable {
  private static let AUDIO_BUFFER_SIZE: UInt32 = 1024
  private let speechRecognizer: SFSpeechRecognizer
  private var speechRequest: SFSpeechAudioBufferRecognitionRequest?
  private var speechTask: SFSpeechRecognitionTask?
  private let audioEngine = AVAudioEngine()
  
  /// Init with the device's default locale
  override public convenience init() {
    self.init(speechRecognizer: SFSpeechRecognizer())
  }
  
  /// Init with a locale
  public convenience init(locale: Locale) {
    self.init(speechRecognizer: SFSpeechRecognizer(locale: locale))
  }
  
  private init(speechRecognizer: SFSpeechRecognizer?) {
    guard let speechRecognizer = speechRecognizer else {
      fatalError("Locale not supported. Check SpeechController.supportedLocales() or  SpeechController.localeSupported(locale: Locale)")
    }
    self.speechRecognizer = speechRecognizer
    self.speechRecognizer.defaultTaskHint = .search
    super.init()
  }
  
  /// Helper to get a list of supported locales
  public class func supportedLocales() -> Set<Locale> {
    return SFSpeechRecognizer.supportedLocales()
  }
  
  /// Helper to check if a locale is supported or not
  public class func localeSupported(_ locale: Locale) -> Bool {
    return SFSpeechRecognizer.supportedLocales().contains(locale)
  }
    
  /// Helper to request authorization for voice search
  public func requestAuthorization(_ statusHandler: @escaping (Bool) -> Void) {
    
    SFSpeechRecognizer.requestAuthorization { (authStatus) in
      switch authStatus {
      case .authorized:
          statusHandler(true)
      default:
          statusHandler(false)
      }
    }
  }
  
  public func isRecording() -> Bool {
    return audioEngine.isRunning
  }
  
  /// The method is going to give an infinite stream of speech-to-text until `stopRecording` is called or an error is encounter
  public func startRecording(textHandler: @escaping SpeechTextHandler, errorHandler: @escaping SpeechErrorHandler) {
    requestAuthorization { [weak self] (authStatus) in
      guard let controller = self else { return }
      if authStatus {
        if !controller.audioEngine.isRunning {
          controller.record(textHandler: textHandler, errorHandler: errorHandler)
        }
      } else {
        let errorMsg = "Speech recognizer needs to be authorized first"
        errorHandler(NSError(domain:"com.algolia.speechcontroller", code:1, userInfo:[NSLocalizedDescriptionKey: errorMsg]))
      }
    }
  }
  
  private func record(textHandler: @escaping SpeechTextHandler, errorHandler: @escaping SpeechErrorHandler) {
    
    do{
      try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: .duckOthers)
      try AVAudioSession.sharedInstance().setActive(true)
    }
    catch{
      print(error.localizedDescription)
    }
    
    let node = audioEngine.inputNode
    let recordingFormat = node.outputFormat(forBus: 0)
    
    let speechRequest = SFSpeechAudioBufferRecognitionRequest()
    
    node.installTap(onBus: 0,
                    bufferSize: SpeechController.AUDIO_BUFFER_SIZE,
                    format: recordingFormat) { [weak self] (buffer, _) in
        self?.speechRequest?.append(buffer)
    }
      
    audioEngine.prepare()
    do {
      try audioEngine.start()
    } catch let err {
      errorHandler(err)
      return
    }
    
    speechTask = speechRecognizer.recognitionTask(with: speechRequest) { (result, error) in
      if let r = result {
        let transcription = r.bestTranscription
        let isFinal = r.isFinal
        textHandler(transcription.formattedString, isFinal, nil)
      } else {
        errorHandler(error)
      }
    }
      self.speechRequest = speechRequest
  }
  
  /// Method which will stop the recording
  public func stopRecording() {
    if audioEngine.isRunning {
      speechRequest?.endAudio()
      audioEngine.stop()
      audioEngine.inputNode.removeTap(onBus: 0)
      speechTask?.cancel()
    }
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    speechTask = nil
    speechRequest = nil
  }
  
  deinit {
    stopRecording()
  }
  
}
