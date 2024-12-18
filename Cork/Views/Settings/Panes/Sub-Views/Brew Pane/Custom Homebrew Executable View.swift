//
//  Custom Homebrew Executable View.swift
//  Cork
//
//  Created by David Bureš on 22.05.2024.
//

import SwiftUI
import CorkShared

struct CustomHomebrewExecutableView: View
{
    @AppStorage("customHomebrewPath") var customHomebrewPath: String = ""
    @AppStorage("allowAdvancedHomebrewSettings") var allowAdvancedHomebrewSettings: Bool = false

    @EnvironmentObject var settingsState: SettingsState

    @State private var isShowingCustomLocationDialog: Bool = false
    @State private var isShowingCustomLocationConfirmation: Bool = false

    var body: some View
    {
        Form
        {
            Section
            {
                LabeledContent
                {
                    VStack(alignment: .leading)
                    {
                        GroupBox
                        {
                            PathControl(urlToShow: URL(filePath: AppConstants.shared.brewExecutablePath.path), style: .standard, width: 295)
                                .disabled(true)
                        }

                        Spacer()

                        HStack
                        {
                            Button
                            {
                                isShowingCustomLocationConfirmation = true
                            } label: {
                                Text("settings.brew.custom-homebrew-path.select")
                            }

                            if !customHomebrewPath.isEmpty
                            {
                                Button
                                {
                                    customHomebrewPath = ""
                                } label: {
                                    Text("settings.brew.custom-homebrew-path.reset")
                                }
                            }
                        }
                    }
                } label: {
                    Text("settings.brew.custom-homebrew-path")
                }
            }
        }
        .disabled(!allowAdvancedHomebrewSettings)
        .onChange(of: allowAdvancedHomebrewSettings, perform: { newValue in
            if newValue == false
            {
                if !customHomebrewPath.isEmpty
                {
                    customHomebrewPath = ""
                }
            }
        })
        .fileImporter(
            isPresented: $isShowingCustomLocationDialog,
            allowedContentTypes: [.unixExecutable],
            allowsMultipleSelection: false
        )
        { result in
            switch result
            {
            case .success(let success):
                if success.first!.lastPathComponent == "brew"
                {
                    AppConstants.shared.logger.info("Valid brew executable: \(success.first!.path)")

                    customHomebrewPath = success.first!.path
                }
                else
                {
                    AppConstants.shared.logger.error("Not a valid brew executable")

                    settingsState.alertType = .customHomebrewLocationNotABrewExecutable(executablePath: success.first!.path)
                    settingsState.isShowingAlert = true
                }
            case .failure(let failure):
                AppConstants.shared.logger.error("Failure: \(failure)")

                settingsState.alertType = .customHomebrewLocationNotAnExecutableAtAll
                settingsState.isShowingAlert = true
            }
        }
        .confirmationDialog(
            Text("settings.brew.custom-homebrew-path.confirmation.title"),
            isPresented: $isShowingCustomLocationConfirmation
        )
        {
            Button
            {
                isShowingCustomLocationDialog = true
            } label: {
                Text("settings.brew.custom-homebrew-path.confirmation.confirm")
            }
        } message: {
            Text("settings.brew.custom-homebrew-path.confirmation.message")
        }
    }
}
