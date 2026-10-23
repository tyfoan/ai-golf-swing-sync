//
//  AppDelegate.swift
//  golf-sync-swing
//
//  Keeps the iPhone app in portrait. The generated Info.plist still lists the
//  landscape orientations, but onboarding, the paywall and the camera guide are
//  portrait layouts: in landscape onboarding lost both of its buttons and the
//  paywall hid Restore, Terms and Privacy. This mask takes precedence over the plist.
//

import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        .portrait
    }
}
