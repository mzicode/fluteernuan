import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    guard
      let windowScene = scene as? UIWindowScene,
      let appDelegate = UIApplication.shared.delegate as? AppDelegate
    else {
      return
    }

    let appWindow = UIWindow(windowScene: windowScene)
    let flutterViewController = FlutterViewController(
      engine: appDelegate.flutterEngine,
      nibName: nil,
      bundle: nil
    )
    appWindow.rootViewController = flutterViewController
    window = appWindow
    appWindow.makeKeyAndVisible()

    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }
}
