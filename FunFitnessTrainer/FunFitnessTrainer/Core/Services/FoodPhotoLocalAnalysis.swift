import CoreImage
import UIKit
import Vision

/// On-device barcode + nutrition-label reading so packaged food photos
/// do not depend on a large AI upload over flaky cellular.
enum FoodPhotoLocalAnalysis {
    private static let visionQueue = DispatchQueue(label: "funfitness.vision", qos: .userInitiated)

    static func detectBarcode(in image: UIImage) async -> String? {
        await withCheckedContinuation { continuation in
            visionQueue.async {
                guard let cgImage = scaledCGImage(from: image, maxEdge: 2200) else {
                    continuation.resume(returning: nil)
                    return
                }
                let orientation = image.cgImageOrientation
                if let code = confirmed(detectBarcodeSync(in: cgImage, orientation: orientation)) {
                    continuation.resume(returning: code)
                    return
                }
                // Bars at the bottom of a carton often fail until they're cropped larger.
                if let lower = cropBottom(cgImage, fraction: 0.6),
                   let code = confirmed(detectBarcodeSync(in: lower, orientation: orientation)) {
                    continuation.resume(returning: code)
                    return
                }
                if let band = centerBand(cgImage),
                   let code = confirmed(detectBarcodeSync(in: band, orientation: orientation)) {
                    continuation.resume(returning: code)
                    return
                }
                // Quiet zone clipped (digit printed on the carton edge). Read the human-readable UPC.
                if let band = centerBand(cgImage),
                   let code = barcodeDigits(in: band, orientation: orientation) {
                    continuation.resume(returning: code)
                    return
                }
                continuation.resume(returning: barcodeDigits(in: cgImage, orientation: orientation))
            }
        }
    }

    /// Digits printed under the bars. Vision often misses the graphic when the carton edge
    /// eats the quiet zone, but the numbers are still readable: "8 98999 01181 3".
    static func barcodeDigits(in lines: [String]) -> String? {
        let joined = lines.joined(separator: " ")
        let runs = digitRuns(in: joined)
        var found: [String] = []
        var clipped: [String] = []

        for start in runs.indices {
            var digits = ""
            var end = start
            while end < runs.count {
                if end > start {
                    let gap = joined[runs[end - 1].end..<runs[end].start]
                    if gap.contains(where: { !$0.isWhitespace }) { break }
                }
                let next = digits + runs[end].digits
                if next.count > 14 { break }
                digits = next
                if let code = gtinIfValid(digits) {
                    found.append(code)
                } else if let repaired = repairedUPCCheckDigit(digits, runs: runs, start: start, end: end) {
                    // The check digit sits on the carton corner and is the digit OCR misses.
                    found.append(repaired)
                }
                end += 1
                // "96633 83142 2" before a lot code ("25V120778") gets glued on.
                if end == start + 3,
                   runs[start].digits.count == 5,
                   runs[start + 1].digits.count == 5,
                   runs[start + 2].digits.count == 1,
                   let restored = gtinByRestoringLeadingDigit(
                       runs[start].digits + runs[start + 1].digits,
                       checkDigit: runs[start + 2].digits
                   ) {
                    found.append(restored)
                }
            }

            // "8 88849 01158" with the check digit cut off the wrapper edge.
            // A lot code on the next line ("400771") is longer than one digit, so the
            // loop stops before consuming it. That lot code is not the missing check digit.
            let last = end - 1
            if last == start + 2,
               runs[start].digits.count == 1,
               runs[start + 1].digits.count == 5,
               runs[start + 2].digits.count == 5,
               let restored = gtinByAddingCheckDigit(
                   runs[start].digits + runs[start + 1].digits + runs[start + 2].digits
               ) {
                clipped.append(restored)
            }

            // "49000 06101" on a can. The cylinder hides both guard digits,
            // the leading 0 and the check digit. US grocery UPCs use number system 0.
            let pairGap = last == start + 1
                ? joined[runs[start].end..<runs[start + 1].start]
                : nil
            if last == start + 1,
               runs[start].digits.count == 5,
               runs[start + 1].digits.count == 5,
               let pairGap, pairGap.allSatisfy(\.isWhitespace), pairGap.count <= 3,
               let restored = gtinByAddingCheckDigit(
                   "0" + runs[start].digits + runs[start + 1].digits
               ) {
                clipped.append(restored)
            }

        }

        return found.first { $0.count >= 12 } ?? found.first ?? clipped.first
    }

    private struct DigitRun {
        let digits: String
        let start: String.Index
        let end: String.Index
    }

    private static func digitRuns(in text: String) -> [DigitRun] {
        var runs: [DigitRun] = []
        var index = text.startIndex
        while index < text.endIndex {
            if text[index].isNumber {
                let start = index
                while index < text.endIndex, text[index].isNumber {
                    index = text.index(after: index)
                }
                runs.append(DigitRun(digits: String(text[start..<index]), start: start, end: index))
            } else {
                index = text.index(after: index)
            }
        }
        return runs
    }

    /// GS1 check digit (UPC-A, EAN-13, GTIN-14). Rejects article numbers like "1788968".
    static func gtinIfValid(_ digits: String) -> String? {
        let code = digits.filter(\.isNumber)
        guard [8, 12, 13, 14].contains(code.count), isValidGTIN(code) else { return nil }
        return code
    }

    /// 10 data digits plus a printed check digit, missing the number-system digit.
    static func gtinByRestoringLeadingDigit(_ body: String, checkDigit: String) -> String? {
        let digits = body.filter(\.isNumber)
        guard digits.count == 10, let expected = Int(checkDigit), (0...9).contains(expected) else { return nil }
        for lead in 0...9 {
            let candidate = "\(lead)" + digits
            guard gtinCheckDigit(for: candidate) == expected else { continue }
            let full = candidate + String(expected)
            if isValidGTIN(full) { return full }
        }
        return nil
    }

    /// 11 data digits of a UPC-A whose check digit was cut off the frame.
    static func gtinByAddingCheckDigit(_ body: String) -> String? {
        let digits = body.filter(\.isNumber)
        guard digits.count == 11 else { return nil }
        let full = digits + String(gtinCheckDigit(for: digits))
        return isValidGTIN(full) ? full : nil
    }

    private static func isValidGTIN(_ digits: String) -> Bool {
        let nums = digits.compactMap { Int(String($0)) }
        guard nums.count == digits.count, nums.count >= 8 else { return false }
        let expected = gtinCheckDigit(for: String(digits.dropLast()))
        return expected == nums.last
    }

    private static func gtinCheckDigit(for body: String) -> Int {
        let nums = body.compactMap { Int(String($0)) }
        var sum = 0
        for (offset, value) in nums.reversed().enumerated() {
            sum += value * (offset % 2 == 0 ? 3 : 1)
        }
        return (10 - (sum % 10)) % 10
    }

    private static func cropBottom(_ image: CGImage, fraction: CGFloat) -> CGImage? {
        let height = image.height
        let cropHeight = Int(CGFloat(height) * fraction)
        guard cropHeight > 40, cropHeight < height else { return nil }
        let rect = CGRect(x: 0, y: height - cropHeight, width: image.width, height: cropHeight)
        return image.cropping(to: rect)
    }

    static func normalizedBarcode(_ raw: String) -> String? {
        let digits = raw.filter(\.isNumber)
        if [8, 12, 13, 14].contains(digits.count) { return digits }
        // UPC-E is sometimes 6 digits. GS1 strings are longer than the GTIN.
        if digits.count == 6 || digits.count == 7 { return digits }
        if digits.count > 14 {
            let tail14 = String(digits.suffix(14))
            if tail14.count == 14 { return tail14 }
        }
        return nil
    }

    /// Same reader that locks a still photo. A center crop drops the Coke can's
    /// leading 0 and check digit, which sit outside the bars, so the whole frame is scanned.
    static func readLiveBarcode(
        in pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) -> String? {
        let alternate: CGImagePropertyOrientation = orientation == .up ? .down : .up
        for candidate in [orientation, alternate] {
            guard let upright = renderedUpright(pixelBuffer, orientation: candidate) else { continue }
            if let code = retailCode(readBarcode(in: upright, orientation: .up)) {
                return code
            }
            if let code = retailCode(readBarcode(in: upright, orientation: .down)) {
                return code
            }
        }
        return nil
    }

    /// Human-readable UPC. A can is often turned so the nutrition panel is upright and the bars are upside down.
    static func readPrintedBarcode(in image: CGImage) -> String? {
        let fastPasses: [CGImagePropertyOrientation] = [.up, .down, .right, .left]
        for pass in fastPasses {
            if let code = barcodeDigits(in: recognizeLinesSync(in: image, orientation: pass, level: .fast)) {
                return code
            }
        }
        for pass in [CGImagePropertyOrientation.up, .down] {
            if let code = barcodeDigits(in: recognizeLinesSync(in: image, orientation: pass, level: .accurate)) {
                return code
            }
        }
        return nil
    }

    static func copyUpright(
        _ pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) -> CGImage? {
        renderedUpright(pixelBuffer, orientation: orientation)
    }

    /// 12/13/14-digit retail codes only. A 6-digit false UPC-E must not lock the scanner
    /// before the real EAN-13 on the same bag is read.
    private static func retailCode(_ code: String?) -> String? {
        guard let code, acceptedBarcode(code, allowsShortUPCE: false) else { return nil }
        return code
    }

    /// Wide middle slice matching the barcode reticle.
    private static func centerBand(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        let bandWidth = Int(CGFloat(width) * 0.92)
        let bandHeight = Int(CGFloat(height) * 0.42)
        guard bandWidth > 40, bandHeight > 40, bandWidth < width || bandHeight < height else { return nil }
        let rect = CGRect(
            x: (width - bandWidth) / 2,
            y: (height - bandHeight) / 2,
            width: bandWidth,
            height: bandHeight
        )
        return image.cropping(to: rect)
    }

    private static let frameContext = CIContext(options: [.cacheIntermediates: false])

    private static func renderedUpright(
        _ pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) -> CGImage? {
        let image = CIImage(cvPixelBuffer: pixelBuffer).oriented(orientation)
        guard image.extent.width > 20, image.extent.height > 20 else { return nil }
        return frameContext.createCGImage(image, from: image.extent)
    }

    /// 8/12/13/14-digit codes must pass the GS1 check.
    /// Six- and seven-digit payloads are UPC-E only. Lot codes like "400771" are the same length
    /// and must not lock the scanner when a retail symbology did not read them.
    static func acceptedBarcode(_ raw: String, allowsShortUPCE: Bool = false) -> Bool {
        let digits = raw.filter(\.isNumber)
        if digits.count == 6 || digits.count == 7 { return allowsShortUPCE }
        return gtinIfValid(digits) != nil
    }

    struct ScannedCodeCandidate {
        let raw: String
        let isUPCE: Bool
    }

    /// Prefer a checksum-valid retail code over a short UPC-E or a false partial read.
    static func preferredScan(_ candidates: [ScannedCodeCandidate]) -> String? {
        let accepted = candidates.compactMap { candidate -> String? in
            guard let code = normalizedBarcode(candidate.raw),
                  acceptedBarcode(code, allowsShortUPCE: candidate.isUPCE) else { return nil }
            return code
        }
        return accepted.max { scanRank($0) < scanRank($1) }
    }

    private static func scanRank(_ code: String) -> Int {
        if code.count >= 12 { return 100 + code.count }
        if code.count == 8 { return 50 }
        return code.count
    }

    private static func confirmed(_ code: String?) -> String? {
        // `readBarcode` already dropped non-UPC-E short payloads. A 6-digit code here is UPC-E.
        guard let code, acceptedBarcode(code, allowsShortUPCE: true) else { return nil }
        return code
    }

    /// "8 98999 01181 8" when the corner digit was misread. Rebuild the check from the first 11.
    private static func repairedUPCCheckDigit(
        _ digits: String,
        runs: [DigitRun],
        start: Int,
        end: Int
    ) -> String? {
        guard digits.count == 12, end == start + 3, end < runs.count else { return nil }
        guard runs[start].digits.count == 1,
              runs[start + 1].digits.count == 5,
              runs[start + 2].digits.count == 5,
              runs[end].digits.count == 1 else { return nil }
        return gtinByAddingCheckDigit(String(digits.prefix(11)))
    }

    private static func scanOrientations(
        startingAt orientation: CGImagePropertyOrientation
    ) -> [CGImagePropertyOrientation] {
        var ordered = [orientation, CGImagePropertyOrientation.right, .up, .left, .down]
        var unique: [CGImagePropertyOrientation] = []
        for candidate in ordered where !unique.contains(candidate) {
            unique.append(candidate)
        }
        return unique
    }

    private static func barcodeDigits(
        in cgImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) -> String? {
        for candidate in scanOrientations(startingAt: orientation) {
            let lines = recognizeLinesSync(in: cgImage, orientation: candidate, level: .accurate)
            if let code = barcodeDigits(in: lines) {
                return code
            }
        }
        return nil
    }

    private static func detectBarcodeSync(
        in cgImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) -> String? {
        let orientations: [CGImagePropertyOrientation] = [orientation, .up, .right, .left, .down]
        var tried = Set<CGImagePropertyOrientation>()
        for candidate in orientations where tried.insert(candidate).inserted {
            if let code = readBarcode(in: cgImage, orientation: candidate) {
                return code
            }
        }
        return nil
    }

    private static func readBarcode(
        in cgImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) -> String? {
        var found: String?
        let request = VNDetectBarcodesRequest { request, _ in
            let codes = (request.results as? [VNBarcodeObservation]) ?? []
            found = preferredScan(codes.map { observation in
                ScannedCodeCandidate(
                    raw: observation.payloadStringValue ?? "",
                    isUPCE: observation.symbology == .upce
                )
            })
        }
        request.symbologies = VNDetectBarcodesRequest.supportedSymbologies
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        try? handler.perform([request])
        return found
    }

    private static func scaledCGImage(from image: UIImage, maxEdge: Int) -> CGImage? {
        guard let source = image.cgImageForAnalysis() else { return nil }
        let longest = max(source.width, source.height)
        guard longest > maxEdge else { return source }

        let scale = CGFloat(maxEdge) / CGFloat(longest)
        let width = max(Int(CGFloat(source.width) * scale), 1)
        let height = max(Int(CGFloat(source.height) * scale), 1)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return source }

        ctx.interpolationQuality = .medium
        ctx.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx.makeImage() ?? source
    }

    /// Reads Calories / Protein / Carbs / Fat from a Nutrition Facts panel when visible.
    static func readNutritionLabel(from image: UIImage) async -> FoodAnalysisResult? {
        parseNutritionFacts(from: await recognizedLines(from: image))
    }

    /// Best-effort on-device text, passed to GPT when local parsing is incomplete.
    static func recognizedLines(from image: UIImage) async -> [String] {
        await withCheckedContinuation { continuation in
            visionQueue.async {
                guard let cgImage = scaledCGImage(from: image, maxEdge: 1280) else {
                    continuation.resume(returning: [])
                    return
                }
                let orientation = image.cgImageOrientation
                let fast = recognizeLinesSync(in: cgImage, orientation: orientation, level: .fast)
                // A curved can label often yields a few garbage lines ("Mutrition Facts",
                // "rAlories"). Those must not block the accurate pass.
                if parseNutritionFacts(from: fast) != nil || barcodeDigits(in: fast) != nil {
                    continuation.resume(returning: fast)
                    return
                }
                let accurate = recognizeLinesSync(in: cgImage, orientation: orientation, level: .accurate)
                continuation.resume(returning: accurate.isEmpty ? fast : accurate)
            }
        }
    }

    /// True when OCR saw a Nutrition Facts-style panel (even if macros could not be parsed).
    static func looksLikeNutritionLabel(in image: UIImage) async -> Bool {
        looksLikeNutritionLabelText((await recognizedLines(from: image)).joined(separator: "\n"))
    }

    static func parseNutritionFacts(from lines: [String]) -> FoodAnalysisResult? {
        let cleaned = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return nil }

        let joined = cleaned.joined(separator: "\n")
        guard looksLikeNutritionLabelText(joined) else { return nil }

        guard let rawCalories = calorieValue(in: cleaned, joined: joined),
              rawCalories >= 0, rawCalories < 5000 else { return nil }

        let protein = nutrientValue(
            near: ["protein", "pretein"],
            in: cleaned,
            joined: joined,
            patterns: [
#"pr[eo]tein\s*[:\.]?\s*(\d+(?:\.\d+)?)\s*g"#,
                #"pr[eo]tein\s*[:\.]?\s*(\d+(?:\.\d+)?)"#,
            ],
            requireGramSuffix: true
        ) ?? 0

        let carbs = nutrientValue(
            near: ["carbohydrate", "carbohydrates", "total carb", "total carbs", "carb"],
            in: cleaned,
            joined: joined,
            patterns: [
                #"total\s*carbohydrate[s]?\s*[:\.]?\s*(\d+(?:\.\d+)?)\s*g"#,
                #"carbohydrate[s]?\s*[:\.]?\s*(\d+(?:\.\d+)?)\s*g"#,
                #"total\s*carb[s]?\s*[:\.]?\s*(\d+(?:\.\d+)?)\s*g"#,
            ],
            requireGramSuffix: true
        ) ?? 0

        let fat = nutrientValue(
            near: ["total fat", "fat"],
            in: cleaned,
            joined: joined,
            patterns: [
                #"total\s*fat\s*[:\.]?\s*(\d+(?:\.\d+)?)\s*g"#,
                #"\bfat\s*[:\.]?\s*(\d+(?:\.\d+)?)\s*g"#,
            ],
            requireGramSuffix: true,
            preferFirstMatchingLabel: "total fat"
        ) ?? 0

        // Diet drinks / extracts: 0–40 kcal with 0g macros is valid.
        // A 200+ kcal "label" with no macros is almost always a bad OCR read.
        let calories = MacroTrackingEngine.normalizedEnergy(
            reportedCalories: rawCalories,
            proteinG: protein,
            carbsG: carbs,
            fatG: fat
        )

        if protein + carbs + fat == 0 && calories > 40 {
            return nil
        }

        let productName = guessProductName(from: cleaned)
        return FoodAnalysisResult(
            calories: calories,
            proteinG: protein,
            carbsG: carbs,
            fatG: fat,
            items: [productName],
            confidence: protein + carbs + fat == 0 ? 0.8 : 0.9,
            assumptions: ["Read on-device from nutrition label. Confirm serving size."],
            labelDetected: true,
            barcode: nil,
            source: .nutritionLabelOCR
        )
    }

    // MARK: - Vision

    private static func recognizeLinesSync(
        in cgImage: CGImage,
        orientation: CGImagePropertyOrientation,
        level: VNRequestTextRecognitionLevel
    ) -> [String] {
        var texts: [String] = []
        let request = VNRecognizeTextRequest { request, _ in
            let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
            let sorted = observations.sorted { a, b in
                let ay = a.boundingBox.midY
                let by = b.boundingBox.midY
                if abs(ay - by) > 0.02 { return ay > by }
                return a.boundingBox.minX < b.boundingBox.minX
            }
            texts = sorted.compactMap { $0.topCandidates(1).first?.string }
        }
        request.recognitionLevel = level
        request.usesLanguageCorrection = false
        request.customWords = [
            "Nutrition", "Facts", "Calories", "Calorie", "kcal",
            "Protein", "Carbohydrate", "Carbohydrates", "Total Fat",
            "Serving", "Amount", "per serving",
        ]
        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        try? handler.perform([request])
        return texts
    }

    // MARK: - Parsing helpers

    private static func looksLikeNutritionLabelText(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("nutrition facts")
            || lower.contains("mutrition")
            || lower.contains("nutriton")
            || lower.contains("calories")
            || lower.contains("calorles")
            || lower.contains("ralories")
            || lower.contains("alories")
            || lower.contains("kcal")
            || lower.contains("kilojoule")
            || lower.contains(" kj")
            || (lower.contains("protein") && (lower.contains("carbohydrate") || lower.contains("total carb")))
            || (lower.contains("pretein") && lower.contains("carbohydrate"))
    }

    private static func calorieValue(in lines: [String], joined: String) -> Double? {
        let patterns = [
            #"(?:r?alor|calor)(?:ie|ies|les)?\s*[:\.]?\s*(?:less\s+than\s+|<\s*)?(\d+(?:\.\d+)?)"#,
            #"(?:less\s+than\s+|<\s*)(\d+(?:\.\d+)?)\s*(?:r?alor|calor)"#,
            #"(\d+(?:\.\d+)?)\s*(?:r?alor|calor)(?:ie|ies|les)?"#,
            #"energy[^0-9]{0,16}(\d+(?:\.\d+)?)\s*kcal"#,
            #"(\d+(?:\.\d+)?)\s*kcal"#,
            #"kcal\s*[:\.]?\s*(\d+(?:\.\d+)?)"#,
        ]
        if let matched = firstMatch(in: joined, patterns: patterns) {
            return matched
        }
        let kilojoulePatterns = [
            #"(\d+(?:\.\d+)?)\s*k\s*j\b"#,
            #"kilojoules?\s*[:\.]?\s*(\d+(?:\.\d+)?)"#,
        ]
        if let kilojoules = firstMatch(in: joined, patterns: kilojoulePatterns) {
            return kilojoules / 4.184
        }
        return nutrientValue(
            near: ["calories", "calorles", "ralories", "alories", "calorie", "kcal"],
            in: lines,
            joined: joined,
            patterns: patterns,
            requireGramSuffix: false
        )
    }

    /// Prefer regex on full text; fall back to label→nearby-number window for multi-line OCR.
    private static func nutrientValue(
        near labels: [String],
        in lines: [String],
        joined: String,
        patterns: [String],
        requireGramSuffix: Bool,
        preferFirstMatchingLabel: String? = nil
    ) -> Double? {
        if let prefer = preferFirstMatchingLabel,
           let fromPrefer = valueNearLabel(prefer, in: lines, requireGramSuffix: requireGramSuffix) {
            return fromPrefer
        }

        if let matched = firstMatch(in: joined, patterns: patterns) {
            return matched
        }

        for label in labels {
            if let value = valueNearLabel(label, in: lines, requireGramSuffix: requireGramSuffix) {
                return value
            }
        }
        return nil
    }

    /// Finds a number on the same line as `label`, or within the next 3 lines
    /// (handles "Calories" / "110" split across Vision observations).
    private static func valueNearLabel(
        _ label: String,
        in lines: [String],
        requireGramSuffix: Bool
    ) -> Double? {
        let needle = label.lowercased()
        for (index, line) in lines.enumerated() {
            let lower = line.lowercased()
            guard lower.contains(needle) else { continue }

            // Same-line number after the label (skip % DV figures when possible).
            if let sameLine = firstNumber(in: line, after: needle, requireGramSuffix: requireGramSuffix) {
                return sameLine
            }

            for offset in 1...3 where index + offset < lines.count {
                let next = lines[index + offset]
                let nextLower = next.lowercased()
                let isOtherNutrientHeader =
                    nextLower.contains("total fat")
                    || nextLower.contains("saturated")
                    || nextLower.contains("trans fat")
                    || nextLower.contains("cholesterol")
                    || nextLower.contains("sodium")
                    || nextLower.contains("carbohydrate")
                    || nextLower.contains("dietary fiber")
                    || nextLower.contains("sugars")
                    || (needle != "protein" && nextLower.contains("protein"))
                || (needle != "calories" && needle != "calorles" && needle != "ralories"
                    && needle != "alories" && needle != "calorie"
                    && (nextLower.contains("calor") || nextLower.contains("alorie")))

                if isOtherNutrientHeader || nextLower.contains("% daily") || nextLower.contains("daily value") {
                    // Number-only line immediately before the next header is still valid.
                    if let pure = pureNumberLine(next, requireGramSuffix: requireGramSuffix) {
                        return pure
                    }
                    break
                }
                if let value = pureNumberLine(next, requireGramSuffix: requireGramSuffix)
                    ?? firstNumber(in: next, after: nil, requireGramSuffix: requireGramSuffix) {
                    return value
                }
            }
        }
        return nil
    }

    private static func pureNumberLine(_ line: String, requireGramSuffix: Bool) -> Double? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = requireGramSuffix
            ? #"^(\d+(?:\.\d+)?)\s*g$"#
            : #"^(\d+(?:\.\d+)?)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let range = Range(match.range(at: 1), in: trimmed),
              let value = Double(trimmed[range]) else { return nil }
        return value
    }

    private static func firstNumber(in text: String, after label: String?, requireGramSuffix: Bool) -> Double? {
        var search = text
        if let label {
            let lower = text.lowercased()
            if let range = lower.range(of: label) {
                search = String(text[range.upperBound...])
            }
        }
        let pattern = requireGramSuffix
            ? #"(\d+(?:\.\d+)?)\s*g\b"#
            : #"(\d+(?:\.\d+)?)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: search, range: NSRange(search.startIndex..., in: search)),
              let range = Range(match.range(at: 1), in: search),
              let value = Double(search[range]) else { return nil }
        // Skip obvious Daily Value percentages when not requiring grams.
        if !requireGramSuffix, search.contains("%"), value <= 100, !search.lowercased().contains("calor") {
            return nil
        }
        return value
    }

    private static func guessProductName(from lines: [String]) -> String {
        let skip = [
            "nutrition facts", "serving size", "amount per", "daily value",
            "% dv", "calories", "calorles", "servings per",
        ]
        for line in lines.prefix(12) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count >= 3, trimmed.count <= 48 else { continue }
            let lower = trimmed.lowercased()
            if skip.contains(where: { lower.contains($0) }) { continue }
            if trimmed.rangeOfCharacter(from: .letters) == nil { continue }
            if Double(trimmed.filter { $0.isNumber || $0 == "." }) != nil && trimmed.filter(\.isLetter).isEmpty {
                continue
            }
            return trimmed
        }
        return "Packaged food"
    }

    private static func firstMatch(in text: String, patterns: [String]) -> Double? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text),
                  let value = Double(text[range]) else { continue }
            return value
        }
        return nil
    }
}

private extension UIImage {
    func cgImageForAnalysis() -> CGImage? {
        if let cgImage { return cgImage }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
        return rendered.cgImage
    }

    var cgImageOrientation: CGImagePropertyOrientation {
        switch imageOrientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
