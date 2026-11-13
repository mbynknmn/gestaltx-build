// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 huamidev
import SwiftUI

struct WelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 14) {
                        BrandMark(size: 52)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L("Welcome to GestaltX")).font(.title3.bold())
                            Text(L("MobileGestalt Editor")).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 8)
                }
                Section(L("Compatibility")) {
                    Text(VersionSupport.range).fontWeight(.medium)
                    LabeledContent("iOS 26.x", value: L("Unsupported"))
                    LabeledContent("iOS", value: "\(UIDevice.current.systemVersion) (\(VersionSupport.label))")
                    Text(L("System access and available features vary by OS version, device and signing."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section(L("Disclaimer")) {
                    Text(L("Changing MobileGestalt may cause system instability, missing features or a boot loop. Recovering the device may require a restore."))
                    Text(L("Back up your device before making changes, and export a copy of the original plist."))
                    Text(L("Capability flags cannot add missing hardware. Some changes require a device restart."))
                    Text(L("Use only devices you own or are authorized to manage. You are responsible for the changes you choose to apply."))
                    Text(L("This software is provided without warranty. Read the included license before use."))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(L("Welcome"))
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                Button(action: onContinue) {
                    Text(L("I Understand, Continue")).fontWeight(.semibold).frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .padding().background(.regularMaterial)
            }
        }
        .interactiveDismissDisabled()
    }
}
