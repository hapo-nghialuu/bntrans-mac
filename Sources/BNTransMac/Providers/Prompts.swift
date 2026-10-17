import Foundation

/// Ported verbatim from extension/src/services/ai-providers.js
func imageOCRPrompt(targetLang: String) -> String {
    """
    Extract ALL text visible in this image and translate it to \(targetLang).
    Reply with ONLY a JSON object — no markdown fences, no extra text:
    {"segments":[{"box":[yMin,xMin,yMax,xMax],"source":"...","translation":"..."}]}
    Rules:
    - box: bounding box of EACH text line/block in the image, normalized to 0-1000
    - Merge nearby lines of the same paragraph into one segment
    - If the image contains no readable text, reply: {"segments":[]}
    """
}

func imageExplainPrompt(targetLang: String) -> String {
    """
    Look at this image, read the text it contains, and explain its meaning concisely in \(targetLang).
    Reply with plain text only — 1-3 short paragraphs, no markdown.
    """
}

/// System prompt for the text-translate path (selection → panel) — mirrors
/// buildSystemPrompt() in extension/src/services/prompt.js.
func textTranslatePrompt(targetLang: String) -> String {
    """
    You are a translation engine. Translate the user's text into \(targetLang).
    Reply with ONLY the translation — no explanations, no quotes, no extra text.
    Keep the original formatting (line breaks, lists).
    """
}
