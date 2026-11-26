import Testing
@testable import TagwerkCore

struct BarcodeTests {
    @Test func normalized_acceptsEAN13EAN8UPCAAndGTIN14() {
        #expect(Barcode.normalized("4008400404127") == "4008400404127", "EAN-13")
        #expect(Barcode.normalized("96385074") == "96385074", "EAN-8")
        #expect(Barcode.normalized("036000291452") == "036000291452", "UPC-A (12 digits)")
        #expect(Barcode.normalized("10012345678902") == "10012345678902", "GTIN-14")
    }

    @Test func normalized_rejectsWrongCheckDigit() {
        #expect(Barcode.normalized("4008400404128") == nil)
        #expect(Barcode.normalized("96385075") == nil)
        #expect(Barcode.normalized("036000291453") == nil)
    }

    @Test func normalized_stripsSpacesAndSeparators() {
        #expect(Barcode.normalized("  4008400404127\n") == "4008400404127")
        #expect(Barcode.normalized("4 008400 404127") == "4008400404127")
        #expect(Barcode.normalized("4008400-404127") == "4008400404127")
    }

    @Test func normalized_rejectsLettersAndWrongLengths() {
        #expect(Barcode.normalized("") == nil)
        #expect(Barcode.normalized("abc") == nil)
        #expect(Barcode.normalized("400840040412A") == nil)
        #expect(Barcode.normalized("1234567") == nil, "7 digits")
        #expect(Barcode.normalized("123456789") == nil, "9 digits")
        #expect(Barcode.normalized("12345678901") == nil, "11 digits")
        #expect(Barcode.normalized("123456789012345") == nil, "15 digits")
    }

    @Test func normalized_rejectsNonASCIIDigits() {
        #expect(Barcode.normalized("٤٠٠٨٤٠٠٤٠٤١٢٧") == nil)
    }

    @Test func comparisonKey_treatsUPCAAndEAN13WithLeadingZeroAsOneProduct() {
        #expect(Barcode.comparisonKey("036000291452") == Barcode.comparisonKey("0036000291452"))
        #expect(Barcode.comparisonKey("4008400404127") != Barcode.comparisonKey("036000291452"))
    }

    @Test func comparisonKey_isNilForInvalidCodes() {
        #expect(Barcode.comparisonKey("4008400404128") == nil)
        #expect(Barcode.comparisonKey("x") == nil)
    }
}
