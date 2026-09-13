import XCTest

final class RunnerCallReliabilityUITests: XCTestCase {
  private let app = XCUIApplication()

  private var qaPassword: String {
    guard let value = ProcessInfo.processInfo.environment["QA_PASSWORD"], !value.isEmpty else {
      XCTFail("QA_PASSWORD must be supplied by the test environment")
      return ""
    }
    return value
  }

  override func setUpWithError() throws {
    continueAfterFailure = false
    addUIInterruptionMonitor(withDescription: "System permissions") { alert in
      for label in ["允许", "好", "继续", "Allow", "OK", "Continue"] {
        let button = alert.buttons[label]
        if button.exists {
          button.tap()
          return true
        }
      }
      return false
    }
  }

  private func keepScreenshot(_ name: String) {
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func acceptSystemPermissions(timeout: TimeInterval = 10) {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      let alert = springboard.alerts.firstMatch
      if alert.exists {
        print("QA_SYSTEM_ALERT_BEGIN\n\(alert.debugDescription)\nQA_SYSTEM_ALERT_END")
        let allowButtons = springboard.buttons.matching(
          NSPredicate(
            format: "label == %@ OR label == %@ OR label == %@ OR label == %@ OR label == %@",
            "允许", "好", "继续", "Allow", "OK"
          )
        ).allElementsBoundByIndex
        if let allow = allowButtons.first(where: { $0.exists && $0.isHittable }) {
          allow.tap()
          RunLoop.current.run(until: Date().addingTimeInterval(1))
          continue
        }
      } else if Date().timeIntervalSince(deadline) < -2 {
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        continue
      }
      break
    }
  }

  private func waitForAny(_ labels: [String], timeout: TimeInterval) -> XCUIElement? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      for label in labels {
        let queries = [
          app.buttons[label], app.staticTexts[label], app.otherElements[label],
          app.images[label], app.navigationBars[label], app.tabBars.buttons[label],
        ]
        if let element = queries.first(where: { $0.exists && $0.isHittable }) {
          return element
        }
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }
    return nil
  }

  private func dismissKeyboard() {
    if app.keyboards.count > 0 {
      let hideKeyboard = app.descendants(matching: .any).matching(
        NSPredicate(format: "label == %@ OR label == %@", "隐藏输入法", "Hide keyboard")
      ).firstMatch
      if hideKeyboard.exists && hideKeyboard.isHittable {
        hideKeyboard.tap()
      } else {
        app.typeText("\n")
      }
    }
  }

  private func replaceText(in field: XCUIElement, with value: String) {
    field.tap()
    field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 64))
    field.typeText(value)
  }

  private func loginIfNeeded(username: String, password: String) {
    if let acknowledgement = waitForAny(["我知道了", "Got it"], timeout: 2) {
      acknowledgement.tap()
    }
    if waitForAny(["消息", "联系人", "设置"], timeout: 4) != nil {
      return
    }

    var usernameField = app.textFields.firstMatch
    if !usernameField.waitForExistence(timeout: 3),
       let openLogin = waitForAny(["登录", "Log in", "Login"], timeout: 3) {
      openLogin.tap()
      usernameField = app.textFields.firstMatch
    }
    XCTAssertTrue(usernameField.waitForExistence(timeout: 15), "username field missing\n\(app.debugDescription)")

    replaceText(in: usernameField, with: username)
    // Re-query after editing the username because Flutter can rebuild the
    // semantics tree when focus changes.
    let passwordField = app.secureTextFields.firstMatch
    if passwordField.waitForExistence(timeout: 3), passwordField.isHittable {
      passwordField.tap()
    } else {
      app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.54)).tap()
    }
    app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 64))
    app.typeText(password)
    dismissKeyboard()

    let agreementSwitch = app.switches.firstMatch
    if agreementSwitch.waitForExistence(timeout: 3), agreementSwitch.isHittable {
      let currentValue = String(describing: agreementSwitch.value ?? "0")
      if currentValue == "0" || currentValue.lowercased() == "off" {
        agreementSwitch.tap()
      }
    } else {
      let agreementCandidates = app.descendants(matching: .any).matching(
        NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "同意", "agree")
      ).allElementsBoundByIndex
      if let agreement = agreementCandidates.first(where: { $0.isHittable }) {
        agreement.tap()
      } else {
        let checkboxes = app.checkBoxes.allElementsBoundByIndex
        if let checkbox = checkboxes.first(where: { $0.isHittable }) {
          checkbox.tap()
        }
      }
    }

    let login = waitForAny(["登录", "Log in", "Login"], timeout: 5)
    XCTAssertNotNil(login, "login button missing\n\(app.debugDescription)")
    login?.tap()
    app.tap()
    if let acknowledgement = waitForAny(["我知道了", "Got it"], timeout: 8) {
      acknowledgement.tap()
    }
    XCTAssertNotNil(
      waitForAny(["消息", "联系人", "设置"], timeout: 25),
      "main UI missing after login\n\(app.debugDescription)"
    )
  }

  func testInspectAndLogin() throws {
    let environment = ProcessInfo.processInfo.environment
    let username = environment["QA_USERNAME"] ?? "smoke_bob"
    let password = qaPassword
    app.launch()
    acceptSystemPermissions()
    // iOS Simulator may return to SpringBoard after dismissing the first
    // notification permission sheet. Bring the application back before
    // querying Flutter semantics.
    app.activate()
    app.tap()
    loginIfNeeded(username: username, password: password)
    keepScreenshot("logged-in-\(username)")
    print("QA_UI_TREE_BEGIN\n\(app.debugDescription)\nQA_UI_TREE_END")
  }

  func testInspectContacts() throws {
    app.launch()
    acceptSystemPermissions()
    if let acknowledgement = waitForAny(["我知道了", "Got it"], timeout: 2) {
      acknowledgement.tap()
    }
    let contacts = waitForAny(["联系人", "Contacts"], timeout: 15)
    XCTAssertNotNil(contacts, "contacts tab missing\n\(app.debugDescription)")
    contacts?.tap()
    RunLoop.current.run(until: Date().addingTimeInterval(3))
    keepScreenshot("contacts")
    print("QA_CONTACTS_TREE_BEGIN\n\(app.debugDescription)\nQA_CONTACTS_TREE_END")
  }

  func testInspectAliceChat() throws {
    app.launch()
    acceptSystemPermissions(timeout: 2)
    if let acknowledgement = waitForAny(["我知道了", "Got it"], timeout: 2) {
      acknowledgement.tap()
    }
    loginIfNeeded(username: "smoke_bob", password: qaPassword)

    let messages = app.images.matching(
      NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "消息", "Messages")
    ).firstMatch
    XCTAssertTrue(messages.waitForExistence(timeout: 15), "messages tab missing\n\(app.debugDescription)")
    messages.tap()

    let alice = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "smoke_alice", "Smoke Alice")
    ).firstMatch
    XCTAssertTrue(alice.waitForExistence(timeout: 15), "Alice chat missing\n\(app.debugDescription)")
    alice.tap()
    RunLoop.current.run(until: Date().addingTimeInterval(3))
    keepScreenshot("alice-chat")
    print("QA_ALICE_CHAT_TREE_BEGIN\n\(app.debugDescription)\nQA_ALICE_CHAT_TREE_END")
  }

  func testInspectAliceProfile() throws {
    app.launch()
    acceptSystemPermissions(timeout: 2)
    if let acknowledgement = waitForAny(["我知道了", "Got it"], timeout: 2) {
      acknowledgement.tap()
    }
    loginIfNeeded(username: "smoke_bob", password: qaPassword)

    let messages = app.images.matching(
      NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "消息", "Messages")
    ).firstMatch
    XCTAssertTrue(messages.waitForExistence(timeout: 15), "messages tab missing\n\(app.debugDescription)")
    messages.tap()
    let alice = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "smoke_alice", "Smoke Alice")
    ).firstMatch
    XCTAssertTrue(alice.waitForExistence(timeout: 15), "Alice chat missing\n\(app.debugDescription)")
    alice.tap()

    let header = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS[c] %@", "smoke_alice")
    ).firstMatch
    XCTAssertTrue(header.waitForExistence(timeout: 15), "Alice header missing\n\(app.debugDescription)")
    header.tap()
    RunLoop.current.run(until: Date().addingTimeInterval(3))
    keepScreenshot("alice-profile")
    print("QA_ALICE_PROFILE_TREE_BEGIN\n\(app.debugDescription)\nQA_ALICE_PROFILE_TREE_END")
  }

  private func openAliceProfileForCall() {
    app.launch()
    acceptSystemPermissions(timeout: 2)
    if let acknowledgement = waitForAny(["我知道了", "Got it"], timeout: 2) {
      acknowledgement.tap()
    }
    loginIfNeeded(username: "smoke_bob", password: qaPassword)

    let messages = app.images.matching(
      NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "消息", "Messages")
    ).firstMatch
    XCTAssertTrue(messages.waitForExistence(timeout: 15), "messages tab missing\n\(app.debugDescription)")
    messages.tap()
    let alice = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "smoke_alice", "Smoke Alice")
    ).firstMatch
    XCTAssertTrue(alice.waitForExistence(timeout: 15), "Alice chat missing\n\(app.debugDescription)")
    alice.tap()
    let header = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS[c] %@", "smoke_alice")
    ).firstMatch
    XCTAssertTrue(header.waitForExistence(timeout: 15), "Alice header missing\n\(app.debugDescription)")
    header.tap()
    XCTAssertTrue(app.buttons["通话"].waitForExistence(timeout: 10), "voice call action missing\n\(app.debugDescription)")
  }

  private func startOutgoingCallAndHold(actionLabel: String, evidenceName: String) {
    openAliceProfileForCall()
    let action = app.buttons[actionLabel]
    XCTAssertTrue(action.exists && action.isHittable, "\(actionLabel) action not hittable")
    action.tap()
    acceptSystemPermissions(timeout: 10)

    let callSurface = waitForAny(
      ["取消", "挂断", "呼叫中", "正在呼叫", "Cancel", "End", "Calling"],
      timeout: 20
    )
    XCTAssertNotNil(callSurface, "outgoing call surface missing\n\(app.debugDescription)")
    keepScreenshot("\(evidenceName)-outgoing")
    print("QA_OUTGOING_CALL_READY kind=\(actionLabel)\n\(app.debugDescription)\nQA_OUTGOING_CALL_READY_END")

    let deadline = Date().addingTimeInterval(60)
    while Date() < deadline {
      acceptSystemPermissions(timeout: 1)
      if waitForAny(["消息", "联系人", "设置"], timeout: 1) != nil {
        break
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }
    keepScreenshot("\(evidenceName)-final")
    print("QA_OUTGOING_CALL_FINAL kind=\(actionLabel)\n\(app.debugDescription)\nQA_OUTGOING_CALL_FINAL_END")
  }

  func testOutgoingVoiceHold() throws {
    startOutgoingCallAndHold(actionLabel: "通话", evidenceName: "voice")
  }

  func testOutgoingVideoHold() throws {
    startOutgoingCallAndHold(actionLabel: "视频", evidenceName: "video")
  }

  private func openBobProfileFromAliceForCall() {
    app.launch()
    acceptSystemPermissions(timeout: 10)
    if let acknowledgement = waitForAny(["我知道了", "Got it"], timeout: 2) {
      acknowledgement.tap()
    }
    loginIfNeeded(username: "smoke_alice", password: qaPassword)

    let messages = app.images.matching(
      NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "消息", "Messages")
    ).firstMatch
    XCTAssertTrue(messages.waitForExistence(timeout: 15), "messages tab missing\n\(app.debugDescription)")
    messages.tap()
    let bob = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS[c] %@ OR label CONTAINS[c] %@", "smoke_bob", "Smoke Bob")
    ).firstMatch
    XCTAssertTrue(bob.waitForExistence(timeout: 20), "Bob chat missing\n\(app.debugDescription)")
    bob.tap()
    let header = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS[c] %@", "smoke_bob")
    ).firstMatch
    XCTAssertTrue(header.waitForExistence(timeout: 15), "Bob header missing\n\(app.debugDescription)")
    header.tap()
    XCTAssertTrue(app.buttons["通话"].waitForExistence(timeout: 10), "voice call action missing\n\(app.debugDescription)")
  }

  private func startAliceOutgoingCallAndHold(actionLabel: String) {
    openBobProfileFromAliceForCall()
    let action = app.buttons[actionLabel]
    XCTAssertTrue(action.exists && action.isHittable, "\(actionLabel) action not hittable")
    action.tap()
    acceptSystemPermissions(timeout: 10)
    XCTAssertNotNil(
      waitForAny(["取消", "挂断", "呼叫中", "正在呼叫", "Cancel", "End", "Calling"], timeout: 20),
      "Alice outgoing call surface missing\n\(app.debugDescription)"
    )
    keepScreenshot("alice-to-bob-\(actionLabel)-outgoing")
    print("QA_ALICE_OUTGOING_READY kind=\(actionLabel)")
    RunLoop.current.run(until: Date().addingTimeInterval(60))
    keepScreenshot("alice-to-bob-\(actionLabel)-final")
  }

  func testAliceOutgoingVoiceHold() throws {
    startAliceOutgoingCallAndHold(actionLabel: "通话")
  }

  func testAliceOutgoingVideoHold() throws {
    startAliceOutgoingCallAndHold(actionLabel: "视频")
  }

  private func waitForIncomingCallAndAct(actionLabel: String, holdAfterAction: TimeInterval) {
    app.launch()
    acceptSystemPermissions(timeout: 2)
    loginIfNeeded(username: "smoke_bob", password: qaPassword)
    print("QA_INCOMING_CALL_READY action=\(actionLabel)")

    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let deadline = Date().addingTimeInterval(120)
    var action: XCUIElement?
    while Date() < deadline && action == nil {
      for candidate in [app.buttons[actionLabel], springboard.buttons[actionLabel]] {
        if candidate.exists && candidate.isHittable {
          action = candidate
          break
        }
      }
      if action == nil {
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
      }
    }
    XCTAssertNotNil(action, "incoming \(actionLabel) action missing\nAPP:\n\(app.debugDescription)\nSPRINGBOARD:\n\(springboard.debugDescription)")
    keepScreenshot("incoming-before-\(actionLabel)")
    print("QA_INCOMING_CALL_VISIBLE action=\(actionLabel)")
    action?.tap()
    acceptSystemPermissions(timeout: 8)

    if holdAfterAction > 0 {
      XCTAssertNotNil(waitForAny(["挂断", "End"], timeout: 20), "connected call surface missing\n\(app.debugDescription)")
      keepScreenshot("incoming-connected")
      RunLoop.current.run(until: Date().addingTimeInterval(holdAfterAction))
      if let hangup = waitForAny(["挂断", "End"], timeout: 3) {
        hangup.tap()
      }
    }
    RunLoop.current.run(until: Date().addingTimeInterval(3))
    keepScreenshot("incoming-after-\(actionLabel)")
    print("QA_INCOMING_CALL_FINAL action=\(actionLabel)\n\(app.debugDescription)\nQA_INCOMING_CALL_FINAL_END")
  }

  func testWaitIncomingVoiceAccept() throws {
    waitForIncomingCallAndAct(actionLabel: "接听", holdAfterAction: 12)
  }

  func testWaitIncomingVoiceReject() throws {
    waitForIncomingCallAndAct(actionLabel: "拒绝", holdAfterAction: 0)
  }

  private func springboardIncomingAction(_ labels: [String], timeout: TimeInterval) -> XCUIElement? {
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let inCallService = XCUIApplication(bundleIdentifier: "com.apple.InCallService")
    let deadline = Date().addingTimeInterval(timeout)
    var expandedCompactCall = false
    var openedInCallCard = false
    while Date() < deadline {
      for label in labels {
        for element in [
          springboard.buttons[label], springboard.staticTexts[label],
          springboard.otherElements[label], inCallService.buttons[label],
          inCallService.staticTexts[label], inCallService.otherElements[label],
          app.buttons[label], app.staticTexts[label],
        ] where element.exists && element.isHittable {
          return element
        }
      }
      if !expandedCompactCall {
        let compactCall = springboard.otherElements.matching(
          NSPredicate(
            format: "label CONTAINS[c] %@ OR identifier CONTAINS[c] %@",
            "来电", "systemApertureElementIdentifierCall"
          )
        ).firstMatch
        if compactCall.exists && compactCall.isHittable {
          compactCall.tap()
          expandedCompactCall = true
          RunLoop.current.run(until: Date().addingTimeInterval(1))
          continue
        }
      }
      if expandedCompactCall && !openedInCallCard {
        let inCallCard = springboard.otherElements.matching(
          NSPredicate(format: "identifier BEGINSWITH %@", "card:com.apple.InCallService")
        ).firstMatch
        if inCallCard.exists {
          inCallCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
          openedInCallCard = true
          RunLoop.current.run(until: Date().addingTimeInterval(1))
          continue
        }
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }
    return nil
  }

  private func prepareIncomingCallState() {
    app.launch()
    acceptSystemPermissions(timeout: 2)
    loginIfNeeded(username: "smoke_bob", password: qaPassword)
  }

  func testWaitIncomingWhileBackgrounded() throws {
    prepareIncomingCallState()
    XCUIDevice.shared.press(.home)
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 10))
    print("QA_BACKGROUND_INCOMING_READY")

    let accept = springboardIncomingAction(["接听", "接受", "Accept"], timeout: 60)
    XCTAssertNotNil(accept, "background CallKit accept action missing\n\(springboard.debugDescription)")
    keepScreenshot("background-callkit-incoming")
    print("QA_BACKGROUND_CALLKIT_VISIBLE\n\(springboard.debugDescription)\nQA_BACKGROUND_CALLKIT_VISIBLE_END")
    accept?.tap()
    RunLoop.current.run(until: Date().addingTimeInterval(8))
    keepScreenshot("background-callkit-connected")

    let hangup = springboardIncomingAction(["挂断", "结束", "End"], timeout: 15)
    XCTAssertNotNil(hangup, "background connected hangup action missing")
    hangup?.tap()
    RunLoop.current.run(until: Date().addingTimeInterval(3))
  }

  func testInspectIncomingWhileBackgrounded() throws {
    prepareIncomingCallState()
    XCUIDevice.shared.press(.home)
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 10))
    print("QA_BACKGROUND_INSPECT_READY")
    RunLoop.current.run(until: Date().addingTimeInterval(30))
    keepScreenshot("background-incoming-inspect")
    print("QA_BACKGROUND_INSPECT_TREE_BEGIN\n\(springboard.debugDescription)\nQA_BACKGROUND_INSPECT_TREE_END")
    RunLoop.current.run(until: Date().addingTimeInterval(5))
  }

  func testExpandBackgroundCallKitAndInspect() throws {
    prepareIncomingCallState()
    XCUIDevice.shared.press(.home)
    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    XCTAssertTrue(springboard.wait(for: .runningForeground, timeout: 10))
    print("QA_BACKGROUND_EXPAND_READY")

    let deadline = Date().addingTimeInterval(60)
    var compactCall: XCUIElement?
    while Date() < deadline && compactCall == nil {
      let candidate = springboard.otherElements.matching(
        NSPredicate(
          format: "label CONTAINS[c] %@ OR identifier CONTAINS[c] %@",
          "来电", "systemApertureElementIdentifierCall"
        )
      ).firstMatch
      if candidate.exists {
        compactCall = candidate
      } else {
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
      }
    }
    XCTAssertNotNil(compactCall, "compact CallKit surface missing")
    compactCall?.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
    RunLoop.current.run(until: Date().addingTimeInterval(2))

    let inCallCard = springboard.otherElements.matching(
      NSPredicate(format: "identifier BEGINSWITH %@", "card:com.apple.InCallService")
    ).firstMatch
    if inCallCard.exists {
      inCallCard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
      RunLoop.current.run(until: Date().addingTimeInterval(2))
    }
    keepScreenshot("background-callkit-expanded-inspect")
    print("QA_BACKGROUND_EXPANDED_TREE_BEGIN\n\(springboard.debugDescription)\nQA_BACKGROUND_EXPANDED_TREE_END")
    RunLoop.current.run(until: Date().addingTimeInterval(5))
  }

  func testWaitIncomingAfterProcessTermination() throws {
    prepareIncomingCallState()
    app.terminate()
    XCTAssertTrue(app.wait(for: .notRunning, timeout: 10))
    print("QA_TERMINATED_INCOMING_READY")

    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let reject = springboardIncomingAction(["拒绝", "Decline"], timeout: 60)
    XCTAssertNotNil(reject, "terminated-process CallKit reject action missing\n\(springboard.debugDescription)")
    keepScreenshot("terminated-callkit-incoming")
    print("QA_TERMINATED_CALLKIT_VISIBLE\n\(springboard.debugDescription)\nQA_TERMINATED_CALLKIT_VISIBLE_END")
    reject?.tap()
    RunLoop.current.run(until: Date().addingTimeInterval(3))
  }

  func testWaitIncomingWhileLocked() throws {
    prepareIncomingCallState()
    // XCTest intentionally has no public physical-device lock-button API.
    // The host verifies lock state with CoreDevice before starting the call.
    print("QA_MANUAL_LOCK_REQUIRED")
    RunLoop.current.run(until: Date().addingTimeInterval(20))
    print("QA_LOCKED_INCOMING_READY")

    let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
    let systemCallDeadline = Date().addingTimeInterval(60)
    var systemCallVisible = false
    while Date() < systemCallDeadline && !systemCallVisible {
      let compactCall = springboard.otherElements.matching(
        NSPredicate(
          format: "label CONTAINS[c] %@ OR identifier CONTAINS[c] %@",
          "来电", "systemApertureElementIdentifierCall"
        )
      ).firstMatch
      let inCallService = XCUIApplication(bundleIdentifier: "com.apple.InCallService")
      systemCallVisible = compactCall.exists || inCallService.state != .notRunning
      if !systemCallVisible {
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
      }
    }
    XCTAssertTrue(systemCallVisible, "locked test received only in-app UI; system CallKit missing")
    let reject = springboardIncomingAction(["拒绝", "Decline"], timeout: 60)
    XCTAssertNotNil(reject, "locked CallKit reject action missing\n\(springboard.debugDescription)")
    keepScreenshot("locked-callkit-incoming")
    print("QA_LOCKED_CALLKIT_VISIBLE\n\(springboard.debugDescription)\nQA_LOCKED_CALLKIT_VISIBLE_END")
    reject?.tap()
    RunLoop.current.run(until: Date().addingTimeInterval(3))
  }

  func testInspectSystemNetworkSettings() throws {
    let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    settings.launch()
    XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 15))
    RunLoop.current.run(until: Date().addingTimeInterval(2))
    let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    attachment.name = "system-network-settings"
    attachment.lifetime = .keepAlways
    add(attachment)
    print("QA_SETTINGS_TREE_BEGIN\n\(settings.debugDescription)\nQA_SETTINGS_TREE_END")
  }

  func testInspectVPNSettings() throws {
    let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    settings.launch()
    XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 15))
    let vpn = settings.staticTexts["VPN"]
    XCTAssertTrue(vpn.waitForExistence(timeout: 8), "VPN row missing\n\(settings.debugDescription)")
    vpn.tap()
    RunLoop.current.run(until: Date().addingTimeInterval(2))

    let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    screenshot.name = "vpn-settings"
    screenshot.lifetime = .keepAlways
    add(screenshot)

    let tree = XCTAttachment(string: settings.debugDescription)
    tree.name = "vpn-settings-tree"
    tree.lifetime = .keepAlways
    add(tree)
  }

  private func setVPNEnabled(_ enabled: Bool) {
    let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    settings.launch()
    XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 15))

    var toggle = settings.switches.matching(
      NSPredicate(format: "label BEGINSWITH %@", "VPN状态")
    ).firstMatch
    if !toggle.waitForExistence(timeout: 3) {
      let back = settings.buttons["设置"]
      if back.exists && back.isHittable {
        back.tap()
      }
      let vpn = settings.staticTexts["VPN"]
      XCTAssertTrue(vpn.waitForExistence(timeout: 8), "VPN row missing\n\(settings.debugDescription)")
      vpn.tap()
      toggle = settings.switches.matching(
        NSPredicate(format: "label BEGINSWITH %@", "VPN状态")
      ).firstMatch
    }

    XCTAssertTrue(toggle.waitForExistence(timeout: 8), "VPN toggle missing\n\(settings.debugDescription)")
    let current = String(describing: toggle.value ?? "0")
    let isEnabled = current == "1" || current.lowercased() == "on"
    if isEnabled != enabled {
      toggle.tap()
    }

    let expectedValue = enabled ? "1" : "0"
    let changed = NSPredicate(format: "value == %@", expectedValue)
    expectation(for: changed, evaluatedWith: toggle)
    waitForExpectations(timeout: 12)
    keepScreenshot(enabled ? "vpn-enabled" : "vpn-disabled")
  }

  func testDisableVPNForQA() throws {
    setVPNEnabled(false)
  }

  func testEnableVPNAfterQA() throws {
    setVPNEnabled(true)
  }

  func testEnableLocalNetworkForQA() throws {
    let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    settings.launch()
    XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 15))

    for _ in 0..<3 {
      let back = settings.buttons["设置"]
      if back.exists && back.isHittable {
        back.tap()
      } else {
        break
      }
    }

    let privacy = settings.staticTexts["隐私与安全性"]
    for _ in 0..<5 where !privacy.exists {
      settings.swipeUp()
    }
    XCTAssertTrue(privacy.waitForExistence(timeout: 5), "privacy row missing\n\(settings.debugDescription)")
    privacy.tap()

    let localNetwork = settings.staticTexts["本地网络"]
    for _ in 0..<5 where !localNetwork.exists {
      settings.swipeUp()
    }
    XCTAssertTrue(localNetwork.waitForExistence(timeout: 5), "local network row missing\n\(settings.debugDescription)")
    localNetwork.tap()

    let customerCell = settings.cells["暖邻"]
    XCTAssertTrue(customerCell.exists, "Customer local network row missing\n\(settings.debugDescription)")
    for _ in 0..<10 where !customerCell.isHittable {
      settings.swipeUp()
    }
    XCTAssertTrue(customerCell.isHittable, "Customer local network row not visible\n\(settings.debugDescription)")

    let customerToggle = customerCell.switches.firstMatch
    XCTAssertTrue(customerToggle.waitForExistence(timeout: 8), "Customer local network toggle missing\n\(settings.debugDescription)")
    let toggleCoordinate = customerCell.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
    let current = String(describing: customerToggle.value ?? "0")
    if current == "1" || current.lowercased() == "on" {
      toggleCoordinate.tap()
      expectation(for: NSPredicate(format: "value == %@", "0"), evaluatedWith: customerToggle)
      waitForExpectations(timeout: 8)
    }
    toggleCoordinate.tap()
    expectation(for: NSPredicate(format: "value == %@", "1"), evaluatedWith: customerToggle)
    waitForExpectations(timeout: 8)

    keepScreenshot("local-network-enabled")
    let tree = XCTAttachment(string: settings.debugDescription)
    tree.name = "local-network-settings-tree"
    tree.lifetime = .keepAlways
    add(tree)
  }

  func testInspectWiFiDetails() throws {
    let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
    settings.launch()
    XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 15))

    for _ in 0..<4 {
      let back = settings.buttons["设置"]
      if back.exists && back.isHittable {
        back.tap()
      } else {
        break
      }
    }

    let wifi = settings.staticTexts["无线局域网"]
    XCTAssertTrue(wifi.waitForExistence(timeout: 8), "Wi-Fi row missing\n\(settings.debugDescription)")
    wifi.tap()
    RunLoop.current.run(until: Date().addingTimeInterval(2))

    let currentNetwork = settings.cells.matching(
      NSPredicate(format: "label CONTAINS[c] %@ OR identifier CONTAINS[c] %@", "SGAI-1812", "SGAI-1812")
    ).firstMatch
    XCTAssertTrue(currentNetwork.waitForExistence(timeout: 8), "current Wi-Fi missing\n\(settings.debugDescription)")
    let moreInfo = currentNetwork.buttons["更多信息"]
    if moreInfo.exists && moreInfo.isHittable {
      moreInfo.tap()
    } else {
      currentNetwork.tap()
    }
    RunLoop.current.run(until: Date().addingTimeInterval(2))

    keepScreenshot("wifi-details")
    let tree = XCTAttachment(string: settings.debugDescription)
    tree.name = "wifi-details-tree"
    tree.lifetime = .keepAlways
    add(tree)
  }

  func testProbeLocalBackend() throws {
    let endpoint = ProcessInfo.processInfo.environment["QA_HEALTH_URL"]
      ?? "http://192.168.31.17:8080/health"
    guard let url = URL(string: endpoint) else {
      XCTFail("invalid QA health URL: \(endpoint)")
      return
    }

    let completed = expectation(description: "local backend response")
    var result = "endpoint=\(endpoint)\n"
    let configuration = URLSessionConfiguration.ephemeral
    configuration.timeoutIntervalForRequest = 10
    configuration.timeoutIntervalForResource = 15
    URLSession(configuration: configuration).dataTask(with: url) { data, response, error in
      if let error = error as NSError? {
        result += "errorDomain=\(error.domain)\nerrorCode=\(error.code)\nerror=\(error)\n"
      }
      if let response = response as? HTTPURLResponse {
        result += "status=\(response.statusCode)\nheaders=\(response.allHeaderFields)\n"
      }
      if let data {
        result += "body=\(String(decoding: data, as: UTF8.self))\n"
      }
      completed.fulfill()
    }.resume()
    waitForExpectations(timeout: 20)

    let attachment = XCTAttachment(string: result)
    attachment.name = "local-backend-probe"
    attachment.lifetime = .keepAlways
    add(attachment)
    print("QA_BACKEND_PROBE_BEGIN\n\(result)QA_BACKEND_PROBE_END")
    XCTAssertTrue(result.contains("status=200"), "local backend probe failed:\n\(result)")
  }

  func testInspectSafariBackend() throws {
    let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
    safari.activate()
    XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 15))
    RunLoop.current.run(until: Date().addingTimeInterval(3))

    let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
    screenshot.name = "safari-local-backend"
    screenshot.lifetime = .keepAlways
    add(screenshot)

    let description = safari.debugDescription
    let tree = XCTAttachment(string: description)
    tree.name = "safari-local-backend-tree"
    tree.lifetime = .keepAlways
    add(tree)
    print("QA_SAFARI_TREE_BEGIN\n\(description)\nQA_SAFARI_TREE_END")
  }

}
