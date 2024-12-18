//
//  App State.swift
//  Cork
//
//  Created by David Bureš on 05.02.2023.
//

import AppKit
import Foundation
@preconcurrency import UserNotifications
import CorkShared
import CorkNotifications

/// Class that holds the global state of the app, excluding services
@MainActor
class AppState: ObservableObject
{
    // MARK: - Licensing

    @Published var licensingState: LicensingState = .notBoughtOrHasNotActivatedDemo
    @Published var isShowingLicensingSheet: Bool = false

    // MARK: - Navigation

    @Published var navigationTargetId: UUID?

    // MARK: - Notifications

    @Published var notificationEnabledInSystemSettings: Bool?
    @Published var notificationAuthStatus: UNAuthorizationStatus = .notDetermined

    // MARK: - Stuff for controlling various sheets from the menu bar

    @Published var isShowingInstallationSheet: Bool = false
    @Published var isShowingPackageReinstallationSheet: Bool = false
    @Published var isShowingUninstallationSheet: Bool = false
    @Published var isShowingMaintenanceSheet: Bool = false
    @Published var isShowingFastCacheDeletionMaintenanceView: Bool = false
    @Published var isShowingAddTapSheet: Bool = false
    @Published var isShowingUpdateSheet: Bool = false

    // MARK: - Stuff for controlling the UI in general

    @Published var isSearchFieldFocused: Bool = false

    // MARK: - Brewfile importing and exporting

    @Published var isShowingBrewfileExportProgress: Bool = false
    @Published var isShowingBrewfileImportProgress: Bool = false
    @Published var brewfileImportingStage: BrewfileImportStage = .importing

    @Published var isCheckingForPackageUpdates: Bool = true

    @Published var isShowingUninstallationProgressView: Bool = false
    @Published var isShowingFatalError: Bool = false
    @Published var fatalAlertType: DisplayableAlert? = nil

    @Published var isShowingSudoRequiredForUninstallSheet: Bool = false
    @Published var packageTryingToBeUninstalledWithSudo: BrewPackage?

    @Published var isShowingRemoveTapFailedAlert: Bool = false

    @Published var isShowingIncrementalUpdateSheet: Bool = false

    @Published var isLoadingFormulae: Bool = true
    @Published var isLoadingCasks: Bool = true

    @Published var isLoadingTopPackages: Bool = false
    @Published var failedWhileLoadingTopPackages: Bool = false

    @Published var cachedDownloadsFolderSize: Int64 = AppConstants.shared.brewCachedDownloadsPath.directorySize
    @Published var cachedDownloads: [CachedDownload] = .init()

    private var cachedDownloadsTemp: [CachedDownload] = .init()

    @Published var taggedPackageNames: Set<String> = .init()

    @Published var corruptedPackage: String = ""

    // MARK: - Showing errors

    func showAlert(errorToShow: DisplayableAlert)
    {
        fatalAlertType = errorToShow

        isShowingFatalError = true
    }

    func dismissAlert()
    {
        isShowingFatalError = false

        fatalAlertType = nil
    }

    // MARK: - Notification setup

    func setupNotifications() async
    {
        let notificationCenter: UNUserNotificationCenter = AppConstants.shared.notificationCenter

        let authStatus: UNAuthorizationStatus = await notificationCenter.authorizationStatus()

        switch authStatus
        {
        case .notDetermined:
            AppConstants.shared.logger.debug("Notification authorization status not determined. Will request notifications again")

            await requestNotificationAuthorization()

        case .denied:
            AppConstants.shared.logger.debug("Notifications were refused")

        case .authorized:
            AppConstants.shared.logger.debug("Notifications were authorized")

        case .provisional:
            AppConstants.shared.logger.debug("Notifications are provisional")

        case .ephemeral:
            AppConstants.shared.logger.debug("Notifications are ephemeral")

        @unknown default:
            AppConstants.shared.logger.error("Something got really fucked up about notifications setup")
        }

        notificationAuthStatus = authStatus
    }

    func requestNotificationAuthorization() async
    {
        let notificationCenter: UNUserNotificationCenter = AppConstants.shared.notificationCenter

        do
        {
            try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])

            notificationEnabledInSystemSettings = true
        }
        catch let notificationPermissionsObtainingError as NSError
        {
            AppConstants.shared.logger.error("Notification permissions obtaining error: \(notificationPermissionsObtainingError.localizedDescription, privacy: .public)\nError code: \(notificationPermissionsObtainingError.code, privacy: .public)")

            notificationEnabledInSystemSettings = false
        }
    }

    // MARK: - Initiating the update process from legacy contexts

    @objc func startUpdateProcessForLegacySelectors(_: NSMenuItem!)
    {
        isShowingUpdateSheet = true

        sendNotification(title: String(localized: "notification.upgrade-process-started"))
    }

    func loadCachedDownloadedPackages() async
    {
        let smallestDispalyableSize: Int = .init(cachedDownloadsFolderSize / 50)

        var packagesThatAreTooSmallToDisplaySize: Int = 0

        guard let cachedDownloadsFolderContents: [URL] = try? FileManager.default.contentsOfDirectory(at: AppConstants.shared.brewCachedDownloadsPath, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
        else
        {
            return
        }

        let usableCachedDownloads: [URL] = cachedDownloadsFolderContents.filter { $0.pathExtension != "json" }

        for usableCachedDownload in usableCachedDownloads
        {
            guard var itemName: String = try? usableCachedDownload.lastPathComponent.regexMatch("(?<=--)(.*?)(?=\\.)")
            else
            {
                return
            }

            AppConstants.shared.logger.debug("Temp item name: \(itemName, privacy: .public)")

            if itemName.contains("--")
            {
                do
                {
                    itemName = try itemName.regexMatch(".*?(?=--)")
                }
                catch {}
            }

            guard let itemAttributes = try? FileManager.default.attributesOfItem(atPath: usableCachedDownload.path)
            else
            {
                return
            }

            guard let itemSize = itemAttributes[.size] as? Int
            else
            {
                return
            }

            if itemSize < smallestDispalyableSize
            {
                packagesThatAreTooSmallToDisplaySize = packagesThatAreTooSmallToDisplaySize + itemSize
            }
            else
            {
                cachedDownloads.append(CachedDownload(packageName: itemName, sizeInBytes: itemSize))
            }

            AppConstants.shared.logger.debug("Others size: \(packagesThatAreTooSmallToDisplaySize, privacy: .public)")
        }

        AppConstants.shared.logger.log("Cached downloads contents: \(self.cachedDownloads)")

        cachedDownloads = cachedDownloads.sorted(by: { $0.sizeInBytes < $1.sizeInBytes })

        cachedDownloads.append(.init(packageName: String(localized: "start-page.cached-downloads.graph.other-smaller-packages"), sizeInBytes: packagesThatAreTooSmallToDisplaySize, packageType: .other))
    }
}

private extension UNUserNotificationCenter
{
    func authorizationStatus() async -> UNAuthorizationStatus
    {
        await notificationSettings().authorizationStatus
    }
}

extension AppState
{
    func assignPackageTypeToCachedDownloads(brewData: BrewDataStorage)
    {
        var cachedDownloadsTracker: [CachedDownload] = .init()

        AppConstants.shared.logger.debug("Package tracker in cached download assignment function has \(brewData.installedFormulae.count + brewData.installedCasks.count) packages")

        for cachedDownload in cachedDownloads
        {
            let normalizedCachedPackageName: String = cachedDownload.packageName.onlyLetters

            if brewData.installedFormulae.contains(where: { $0.name.localizedCaseInsensitiveContains(normalizedCachedPackageName) })
            { /// The cached package is a formula
                AppConstants.shared.logger.debug("Cached package \(cachedDownload.packageName) (\(normalizedCachedPackageName)) is a formula")
                cachedDownloadsTracker.append(.init(packageName: cachedDownload.packageName, sizeInBytes: cachedDownload.sizeInBytes, packageType: .formula))
            }
            else if brewData.installedCasks.contains(where: { $0.name.localizedCaseInsensitiveContains(normalizedCachedPackageName) })
            { /// The cached package is a cask
                AppConstants.shared.logger.debug("Cached package \(cachedDownload.packageName) (\(normalizedCachedPackageName)) is a cask")
                cachedDownloadsTracker.append(.init(packageName: cachedDownload.packageName, sizeInBytes: cachedDownload.sizeInBytes, packageType: .cask))
            }
            else
            { /// The cached package cannot be found
                AppConstants.shared.logger.debug("Cached package \(cachedDownload.packageName) (\(normalizedCachedPackageName)) is unknown")
                cachedDownloadsTracker.append(.init(packageName: cachedDownload.packageName, sizeInBytes: cachedDownload.sizeInBytes, packageType: .unknown))
            }
        }

        cachedDownloads = cachedDownloadsTracker
    }
}
