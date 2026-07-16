//
//  GrammarReferenceViewController.swift
//  shizen
//
//  Navigation helpers for opening a grammar point's principle intro screen.
//

import UIKit

enum GrammarReferencePresenter {

    static func open(
        point: GrammarPoint,
        from presenter: UIViewController,
        contextLineID: String? = nil
    ) {
        let detail = GrammarPrincipleStepViewController(
            point: point,
            presentation: .referenceDetail,
            contextLineID: contextLineID
        )
        if let navigationController = presenter.navigationController {
            navigationController.pushViewController(detail, animated: true)
        } else {
            let nav = UINavigationController(rootViewController: detail)
            nav.modalPresentationStyle = .pageSheet
            presenter.present(nav, animated: true)
        }
    }

    static func open(
        grammarPointID: String,
        from presenter: UIViewController,
        contextLineID: String? = nil
    ) {
        guard let point = GrammarCurriculum.point(id: grammarPointID) else { return }
        open(point: point, from: presenter, contextLineID: contextLineID)
    }

    static func push(
        grammarPointID: String,
        from navigationController: UINavigationController?,
        contextLineID: String? = nil
    ) {
        guard let navigationController else { return }
        guard let point = GrammarCurriculum.point(id: grammarPointID) else { return }
        let detail = GrammarPrincipleStepViewController(
            point: point,
            presentation: .referenceDetail,
            contextLineID: contextLineID
        )
        navigationController.pushViewController(detail, animated: true)
    }

    static func present(
        grammarPointID: String,
        from presenter: UIViewController,
        contextLineID: String? = nil
    ) {
        open(grammarPointID: grammarPointID, from: presenter, contextLineID: contextLineID)
    }
}
