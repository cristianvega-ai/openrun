/// Messages as an agent writes them, with every kind of block and style.
enum MarkdownSamples {
    static let messages = [
        """
        ## The plan

        I read **`Transcript.swift`** and the *tests*. Three changes:

        1. Add a [limit](https://example.com/limits) to the ~~queue~~ list.
           - keep the `oldest` items
        2. Test it:

           ```swift
           let limits = TranscriptLimits(itemLimit: 2)
           #expect(transcript.items.count == 2)
           ```

        > Note: the *view* reads `removedItemCount`.

        | File | Lines |
        |:--|--:|
        | `Transcript.swift` | 192 |
        | `TranscriptStorage.swift` | 98 |

        ---
        - [x] Read the code
        - [ ] Run `swift test`

        Done. See <https://example.com> or https://example.org/a_(b).
        """,
        "Short answer with a trailing **bold** and `code`\nand a second line.",
        "```\nunclosed code\n# still code",
    ]
}
