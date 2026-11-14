//
//  StaffAccess.swift
//  Whether the signed-in Firebase user has the `staff: true` custom claim.
//  Set it with services/llm-gateway/scripts/set-staff-claim.ts. The servers
//  check the claim themselves; this only decides what UI to show.
//

import FirebaseAuth
import Foundation

enum StaffAccess {
    private(set) static var isStaff = false

    /// Re-reads the claim from the ID token. Called on every auth change.
    static func refresh(forcingRefresh: Bool = false) {
        guard let user = Auth.auth().currentUser, !user.isAnonymous else {
            isStaff = false
            return
        }
        user.getIDTokenResult(forcingRefresh: forcingRefresh) { result, _ in
            let staff = (result?.claims["staff"] as? Bool) == true
            DispatchQueue.main.async { isStaff = staff }
        }
    }

    /// Bearer for Studio `/api/client/*`: the DEBUG QA token when present,
    /// otherwise the user's Firebase ID token (the server checks `staff`).
    static func studioClientBearer(completion: @escaping (String?) -> Void) {
        let token = ContentQAClientToken.resolved
        if !token.isEmpty {
            completion(token)
            return
        }
        guard let user = Auth.auth().currentUser, !user.isAnonymous else {
            completion(nil)
            return
        }
        user.getIDToken { idToken, _ in
            completion(idToken)
        }
    }

    /// QA notes and check-offs can be sent from this build/account.
    static var canUseStudioClientAPI: Bool {
        !ContentQAClientToken.resolved.isEmpty || isStaff
    }
}
