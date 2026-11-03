//
//  ScreenshotQAShortcut.swift
//  shizen
//
//  Debug shortcut: a screenshot asks whether to open the Shohei QA note.
//  The system screenshot is ignored. The note sheet snapshots the view on send.
//

import UIKit

/// A visible screen that already knows how to open the QA note.
protocol ScreenshotQAPresenting: AnyObject {
    /// Opens the note from `presenter` (the screen that was screenshotted).
    /// Returns false when this surface has no note to send.
    func presentScreenshotQANote(from presenter: UIViewController) -> Bool
}

enum ScreenshotQAShortcut {
    #if DEBUG
    private static var isOffering = false
    private static var observer: NSObjectProtocol?
    #endif

    static func start() {
        #if DEBUG
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: UIApplication.userDidTakeScreenshotNotification,
            object: nil,
            queue: .main
        ) { _ in
            offerQA()
        }
        #endif
    }

    #if DEBUG
    private static func offerQA() {
        guard !isOffering, let presenter = foregroundPresenter() else { return }
        guard !isQANote(presenter) else { return }
        guard presenter.presentedViewController == nil
            || presenter.presentedViewController?.isBeingDismissed == true else { return }

        let alert = UIAlertController(title: "QA this screen?", message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Not now", style: .cancel) { _ in
            isOffering = false
        })
        alert.addAction(UIAlertAction(title: "Write a note", style: .default) { _ in
            isOffering = false
            presentNoteAfterAlertDismiss(from: presenter)
        })
        isOffering = true
        presenter.present(alert, animated: true)
    }

    /// The alert dismisses itself when the action runs. Present the note after that transition.
    private static func presentNoteAfterAlertDismiss(from presenter: UIViewController) {
        let present = {
            if presenter.presentedViewController != nil {
                presenter.dismiss(animated: true) {
                    openNote(from: presenter)
                }
            } else {
                openNote(from: presenter)
            }
        }
        if let coordinator = presenter.transitionCoordinator {
            coordinator.animate(alongsideTransition: nil) { _ in
                present()
            }
        } else {
            DispatchQueue.main.async(execute: present)
        }
    }

    private static func openNote(from presenter: UIViewController) {
        var current: UIViewController? = presenter
        while let viewController = current {
            if let host = viewController as? ScreenshotQAPresenting,
               host.presentScreenshotQANote(from: presenter) {
                return
            }
            current = viewController.parent
        }
        presentScreenNote(from: presenter)
    }

    /// Note for a screen that has no lesson or scene context.
    private static func presentScreenNote(from presenter: UIViewController) {
        let typeName = String(describing: type(of: presenter))
        let title = screenTitle(of: presenter)
        DialogueContentQANoteViewController.present(
            from: presenter,
            source: .screen,
            sourceId: typeName,
            focusTitle: title,
            focusDetailLines: ["Type: \(typeName)"],
            lessonTitle: title,
            lessonID: typeName,
            studioLink: "screen/\(typeName)",
            forcesScreenshot: true
        )
    }

    private static func foregroundPresenter() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        let window = scene?.windows.first { $0.isKeyWindow } ?? scene?.windows.first
        return topViewController(from: window?.rootViewController)
    }

    private static func topViewController(from base: UIViewController?) -> UIViewController? {
        if let navigation = base as? UINavigationController {
            return topViewController(from: navigation.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            return topViewController(from: tab.selectedViewController)
        }
        if let presented = base?.presentedViewController, !presented.isBeingDismissed {
            return topViewController(from: presented)
        }
        return base
    }

    private static func isQANote(_ viewController: UIViewController) -> Bool {
        if viewController is DialogueContentQANoteViewController { return true }
        if let navigation = viewController.navigationController ?? (viewController as? UINavigationController) {
            return navigation.viewControllers.contains { $0 is DialogueContentQANoteViewController }
        }
        return false
    }

    private static func screenTitle(of viewController: UIViewController) -> String {
        let candidates = [viewController.navigationItem.title, viewController.title]
        for candidate in candidates {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !trimmed.isEmpty { return trimmed }
        }
        return String(describing: type(of: viewController))
    }
    #endif
}
