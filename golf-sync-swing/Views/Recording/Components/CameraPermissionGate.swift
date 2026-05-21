//
//  CameraPermissionGate.swift
//  golf-sync-swing
//
//  Shown over the recording tab when the user has not yet granted camera
//  access. Routes to the system prompt the first time and to Settings after
//  the user has denied or system policy has restricted the device.
//

import AVFoundation
import SwiftUI

struct CameraPermissionGate: View {
    let status: AVAuthorizationStatus
    let onPrimaryAction: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 28) {
                Image(systemName: "video.slash.fill")
                    .font(.system(size: 64, weight: .regular))
                    .foregroundStyle(.white.opacity(0.75))

                VStack(spacing: 10) {
                    Text(title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 12)

                Button(action: onPrimaryAction) {
                    Text(buttonTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.fairwayGreen)
                        .clipShape(Capsule())
                }
                .disabled(status == .restricted)
                .opacity(status == .restricted ? 0.5 : 1.0)
            }
            .padding(.horizontal, 32)
        }
    }

    private var title: LocalizedStringKey {
        switch status {
        case .restricted:
            return "Camera Restricted"
        default:
            return "Camera Access Needed"
        }
    }

    private var message: LocalizedStringKey {
        switch status {
        case .restricted:
            return "Camera use is restricted on this device. Check Screen Time or device management settings."
        case .denied:
            return "Enable the camera in Settings to record and analyze swings."
        default:
            return "Golf Sync Swing needs the camera to record and analyze your swings."
        }
    }

    private var buttonTitle: LocalizedStringKey {
        switch status {
        case .notDetermined:
            return "Enable Camera"
        case .denied:
            return "Open Settings"
        case .restricted:
            return "Restricted"
        default:
            return "Enable Camera"
        }
    }
}

#Preview("Not Determined") {
    CameraPermissionGate(status: .notDetermined, onPrimaryAction: {})
}

#Preview("Denied") {
    CameraPermissionGate(status: .denied, onPrimaryAction: {})
}

#Preview("Restricted") {
    CameraPermissionGate(status: .restricted, onPrimaryAction: {})
}
