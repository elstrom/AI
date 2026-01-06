import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  
  // Channel for receiving scan data from ScanAI
  private var scanDataChannel: FlutterMethodChannel?
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    let controller = window?.rootViewController as! FlutterViewController
    
    // Setup channel for communicating scan data to Flutter
    scanDataChannel = FlutterMethodChannel(
      name: "com.posai/scan_data",
      binaryMessenger: controller.binaryMessenger
    )
    
    GeneratedPluginRegistrant.register(with: self)
    
    // Check if app was launched via URL
    if let url = launchOptions?[.url] as? URL {
      handleIncomingURL(url)
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // Handle URL when app is already running
  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey : Any] = [:]
  ) -> Bool {
    return handleIncomingURL(url)
  }
  
  // Handle Universal Links (iOS 13+)
  override func application(
    _ application: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
       let url = userActivity.webpageURL {
      return handleIncomingURL(url)
    }
    return false
  }
  
  /// Parse incoming URL from ScanAI and send to Flutter
  @discardableResult
  private func handleIncomingURL(_ url: URL) -> Bool {
    guard url.scheme == "posai" else {
      return false
    }
    
    print("[PosAI] Received URL: \(url.absoluteString)")
    
    // Parse path: posai://scan-result?data=<base64>
    guard url.host == "scan-result",
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let queryItems = components.queryItems,
          let dataItem = queryItems.first(where: { $0.name == "data" }),
          let base64Data = dataItem.value else {
      print("[PosAI] Invalid URL format")
      return false
    }
    
    // Decode Base64 to JSON string
    guard let decodedData = Data(base64Encoded: base64Data),
          let jsonString = String(data: decodedData, encoding: .utf8) else {
      print("[PosAI] Failed to decode Base64 data")
      return false
    }
    
    print("[PosAI] Decoded JSON: \(jsonString.prefix(100))...")
    
    // Send to Flutter via MethodChannel
    DispatchQueue.main.async { [weak self] in
      self?.scanDataChannel?.invokeMethod("onScanDataReceived", arguments: jsonString)
    }
    
    return true
  }
}
