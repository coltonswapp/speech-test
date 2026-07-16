//
//  merge-grammar-content
//  Merges approved per-point JSON files into the bundled n5.grammar.json.
//

import Foundation
import GrammarContentKit

let arguments = CommandLine.arguments
guard arguments.count >= 3 else {
    fputs(
        "Usage: merge-grammar-content <content-root> <output-json>\n"
            + "Example: merge-grammar-content content/n5 shizen/Resources/Grammar/n5.grammar.json\n",
        stderr
    )
    exit(1)
}

let contentRoot = URL(fileURLWithPath: arguments[1], isDirectory: true)
let outputURL = URL(fileURLWithPath: arguments[2])

do {
    let result = try ContentMerge.mergeApprovedPoints(from: contentRoot, to: outputURL)
    if result.patchedExistingBundle {
        print(
            "Patched \(result.updatedPointIDs.count + result.addedPointIDs.count) approved points "
                + "(\(result.preservedPointCount) unchanged, \(result.curriculum.points.count) total) "
                + "into \(outputURL.path)"
        )
    } else {
        print("Created bundle with \(result.curriculum.points.count) approved points at \(outputURL.path)")
    }
} catch {
    fputs("Merge failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
