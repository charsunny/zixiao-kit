import SwiftUI
import UIKit
import ObjectiveC

/// Installs only the workspace's Find key command on its containing controller.
/// It never becomes first responder, so text selection and typing keep their
/// native focus behavior. The registration is removed when the workspace leaves.
struct NativeSearchCommand: UIViewControllerRepresentable {
    let action: () -> Void

    func makeUIViewController(context: Context) -> SearchCommandInstaller {
        SearchCommandInstaller(action: action)
    }

    func updateUIViewController(_ controller: SearchCommandInstaller, context: Context) {
        controller.action = action
    }

    static func dismantleUIViewController(_ controller: SearchCommandInstaller, coordinator: ()) {
        controller.uninstall()
    }
}

@MainActor
private var searchCommandAssociation: UInt8 = 0

@MainActor
final class SearchCommandInstaller: UIViewController {
    var action: () -> Void
    private weak var installedOn: UIViewController?
    private lazy var command: UIKeyCommand = {
        let command = UIKeyCommand(title: "搜索作品",
                                   action: #selector(UIViewController.poetKitFindWorks(_:)),
                                   input: "f", modifierFlags: .command)
        command.wantsPriorityOverSystemBehavior = true
        return command
    }()

    init(action: @escaping () -> Void) {
        self.action = action
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        view = UIView()
        view.isUserInteractionEnabled = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard let parent, installedOn !== parent else { return }
        uninstall()
        if let reference = objc_getAssociatedObject(parent, &searchCommandAssociation) as? SearchCommandReference,
           let previous = reference.installer, previous !== self {
            previous.uninstall()
        }
        installedOn = parent
        objc_setAssociatedObject(parent, &searchCommandAssociation,
                                 SearchCommandReference(self), .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        parent.addKeyCommand(command)
    }

    override func viewWillDisappear(_ animated: Bool) {
        uninstall()
        super.viewWillDisappear(animated)
    }

    func uninstall() {
        guard let installedOn else { return }
        installedOn.removeKeyCommand(command)
        if let reference = objc_getAssociatedObject(installedOn, &searchCommandAssociation) as? SearchCommandReference,
           reference.installer === self {
            objc_setAssociatedObject(installedOn, &searchCommandAssociation, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        self.installedOn = nil
    }
}

@MainActor
private final class SearchCommandReference {
    weak var installer: SearchCommandInstaller?
    init(_ installer: SearchCommandInstaller) { self.installer = installer }
}

private extension UIViewController {
    @objc func poetKitFindWorks(_ command: UIKeyCommand) {
        var controller: UIViewController? = self
        while let current = controller {
            if let reference = objc_getAssociatedObject(current, &searchCommandAssociation) as? SearchCommandReference,
               let installer = reference.installer {
                installer.action()
                return
            }
            controller = current.parent
        }
    }
}
