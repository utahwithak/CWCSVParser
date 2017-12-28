//
//  CWCSVParser.swift
//  CWCSVParser
//
/**
 Copyright (c) 2017 Carl Wieland

 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.
 **/

import Foundation

fileprivate let CHUNK_SIZE = 512
fileprivate let DOUBLE_QUOTE: Character = "\""
fileprivate let COMMA: Character = ","
fileprivate let OCTOTHORPE: Character = "#"
fileprivate let EQUAL: Character = "="
fileprivate let BACKSLASH: Character = "\\"
fileprivate let NULLCHAR: Character = "\0"

enum CSVError: Int, CustomNSError {
    /// Indicates that a delimited file is incorrectly formatted.
    /// For example, perhaps a double quote is in the wrong position.
    case invalidFormat

    /// all of the lines in the file
    /// must have the same number of fields. If they do not, parsing is aborted and this error is returned.
    case incorrectNumberOfFields

    case invalidDelimiter


    public static var errorDomain: String {
        return "com.datumapps.CSVError"
    }

    var errorCode: Int {
        return self.rawValue
    }

    // To make it work when casting to NSError's
    var errorUserInfo: [String: Any] {
        return [NSLocalizedDescriptionKey: localizedDescription]
    }

    var localizedDescription: String {
        switch self {
        case .invalidFormat: return NSLocalizedString("Invalid CSV Format", bundle: Bundle(for: CSVParser.self), comment: "invalid format error description")
        case .incorrectNumberOfFields: return NSLocalizedString("Keyed Field miss match", bundle: Bundle(for: CSVParser.self), comment: "Unknown error description")
        case .invalidDelimiter: return NSLocalizedString("Missing Delimiter", bundle: Bundle(for: CSVParser.self), comment: "invalid CSV Missing Bundle")
        }
    }

}


@objc protocol ParserDelegate: class {

    /// Indicates that the parser has started parsing the stream
    ///
    /// - Parameter parser: `CSVParser` instance

    @objc optional func parserDidBeginDocument(_ parser: CSVParser)

    /// Indicates that the parser has successfully finished parsing the stream
    /// - Note: This method is not invoked if any error is encountered
    /// - Parameter parser: `CSVParser` instance
    @objc optional func parserDidEndDocument(_ parser: CSVParser)

    /// Indicates the parser has started parsing a line
    ///
    /// - Parameters:
    ///   - parser: `CSVParser` instance
    ///   - line: The 1-based number of the record
    @objc optional func parser(_ parser: CSVParser, didBeginLine line:Int)

    /// Indicates the parser has finished parsing a line
    ///
    /// - Parameters:
    ///   - parser: `CSVParser` instance
    ///   - line: The 1-based number of the record
    @objc optional func parser(_ parser: CSVParser, didEndLine line: Int)

    /// Indicates the parser has parsed a field on the current line
    ///
    /// - Parameters:
    ///   - parser: `CSVParser` instance
    ///   - field: The parsed string. If configured to do so, this string may be sanitized and trimmed
    ///   - index: The 0-based index of the field within the current record
    @objc optional func parser(_ parser: CSVParser, didReadField field: String, at index: Int)

    /// Indicates the parser has encountered a comment
    /// - Note: this method is only invoked if `CSVParser.recognizesComments` is `true`
    /// - Parameters:
    ///   - parser: `CSVParser` instance
    ///   - comment: The parsed comment
    @objc optional func parser(_ parser: CSVParser, didReadComment comment: String)


    /// Indicates the parser encounter an error while parsing
    ///
    /// - Parameters:
    ///   - parser: `CSVParser` instance
    ///   - error: Error that was encountered while parsing.
    @objc optional func parser(_ parser: CSVParser, didFailWithError error: Error)
}

final class CSVParser: NSObject {

    static func parse(inputStream: InputStream, options: CSVParserOptions, delimiter: Character) throws -> [[String]] {

        let parser = CSVParser(stream: inputStream, delimiter: delimiter)

        let aggregator = CSVAggregator()
        parser.delegate = aggregator

        parser.recognizesBackslashesAsEscapes = options.contains(.recognizesBackslashesAsEscapes)
        parser.sanitizesFields = options.contains(.sanitizesFields)
        parser.recognizesComments = options.contains(.recognizesComments)
        parser.trimsWhitespace = options.contains(.trimsWhitespace)
        parser.recognizesLeadingEqualSign = options.contains(.recognizesLeadingEqualSign)

        parser.parse()

        if let error = aggregator.error {
            throw error
        } else {
            return aggregator.lines
        }


    }

    static func parseKeyed(inputStream: InputStream, options: CSVParserOptions, delimiter: Character) throws -> [[String:String]] {

        let parser = CSVParser(stream: inputStream, delimiter: delimiter)

        let aggregator = CSVKeyedAggregator()
        parser.delegate = aggregator

        parser.recognizesBackslashesAsEscapes = options.contains(.recognizesBackslashesAsEscapes)
        parser.sanitizesFields = options.contains(.sanitizesFields)
        parser.recognizesComments = options.contains(.recognizesComments)
        parser.trimsWhitespace = options.contains(.trimsWhitespace)
        parser.recognizesLeadingEqualSign = options.contains(.recognizesLeadingEqualSign)

        parser.parse()

        if let error = aggregator.error {
            throw error
        } else {
            return aggregator.lines
        }

    }

    public weak var delegate: ParserDelegate?

    ///  If `true`, then the parser will removing surrounding double quotes and will unescape characters.
    ///  - Note: default value is `false`
    ///  - Warning: Do not mutate this property after parsing has begun
    public var sanitizesFields = false

    ///  If `true`, then the parser will trim whitespace around fields. If `sanitizesFields` is also `true`, then the sanitized field is also trimmed.
    ///  - Note: default value is `false`
    ///  - Warning: Do not mutate this property after parsing has begun
    public var trimsWhitespace = false

    ///  If `true`, then the parser will allow special characters (delimiter, newline, quote, etc)
    ///  - Note: default value is `false`
    ///  - Warning: Do not mutate this property after parsing has begun
    public var recognizesBackslashesAsEscapes = false

    ///  If `true`, then the parser will interpret any field that begins with an octothorpe as a comment.
    ///  Comments are terminated using an unescaped newline character.
    ///  - Note: default value is `false`
    ///  - Warning: Do not mutate this property after parsing has begun
    public var recognizesComments = false

    ///  If `true`, then quoted fields may begin with an equal sign.
    ///  Some programs produce fields with a leading equal sign to indicate that the contents must be represented exactly.
    ///  - Note: default value is `false`
    ///  - Warning: Do not mutate this property after parsing has begun
    public var recognizesLeadingEqualSign = false

    /// The number of bytes that have been read from the input stream so far
    /// - Note: This property is key-value observable.
    @objc dynamic public private(set) var totalBytesRead: Int = 0

    /// Encoding used in the parsing
    public private(set) var streamEncoding: String.Encoding = .utf8


    /// An initializer to parse a delimited string
    /// Internally it calls the designated initializer and provides a stream of the UTF8 representation of the string as well as the provided delimiter.
    /// - Parameters:
    ///   - delimitedString: String to parse
    ///   - delimiter: he delimiter character to be used when parsing the string. Must not be the double quote or newline character
    public convenience init?(_ delimitedString: String, delimiter: Character = COMMA, options: CSVParserOptions = []) {
        guard let data = delimitedString.data(using: .utf8) else {
            return nil
        }
        let stream = InputStream(data: data)
        self.init(stream: stream, delimiter: delimiter, options: options)
    }

    /// An initializer to parse the contents of URL
    /// Internally it calls the designated initializer and provides a stream to the URL as well as the provided delimiter.
    /// The parser attempts to infer the encoding from the stream.
    ///
    /// - Parameters:
    ///   - url: The `URL` to the delimited file
    ///   - delimiter: The delimiter character to be used when parsing the string. Must not be the double quote or newline character
    public convenience init?(contentsOf url: URL, delimiter: Character = COMMA, options: CSVParserOptions = []) {
        guard let stream = InputStream(url: url) else {
            return nil
        }
        self.init(stream: stream, delimiter: delimiter, options: options)
    }

    /// Designated initializer, parses the stream using delimiter.
    ///
    /// - Parameters:
    ///   - stream: The `InputStream` from which bytes will be read and parsed
    ///   - delimiter: he delimiter character to be used when parsing the stream. Must not be the double quote or newline character
    init(stream: InputStream, delimiter: Character, encoding: String.Encoding? = nil, options: CSVParserOptions = []) {

        self.stream = stream
        stream.open()

        self.delimiter = delimiter

        var invalidSet = CharacterSet.newlines
        invalidSet.insert(charactersIn: "\(DOUBLE_QUOTE)\(delimiter)")
        validFieldCharacters = invalidSet.inverted

        recognizesBackslashesAsEscapes = options.contains(.recognizesBackslashesAsEscapes)
        sanitizesFields = options.contains(.sanitizesFields)
        recognizesComments = options.contains(.recognizesComments)
        trimsWhitespace = options.contains(.trimsWhitespace)
        recognizesLeadingEqualSign = options.contains(.recognizesLeadingEqualSign)


        super.init()

        if let encoding = encoding {
            streamEncoding = encoding
        } else {
            sniffEncoding()
        }

    }

    deinit {
        stream.close()
    }

    public func parse() {


        autoreleasepool {
            delegate?.parserDidBeginDocument?(self)

            guard delimiter != "\n" && delimiter != "\"" else {
                delegate?.parser?(self, didFailWithError: CSVError.invalidDelimiter)
                return
            }

            while parseRecord() { }

            if let error = error {
                if canceled {
                    return
                }
                delegate?.parser?(self, didFailWithError: error)
            } else {
                delegate?.parserDidEndDocument?(self)
            }
        }
    }

    public func cancelParsing() {
        canceled = true
    }


    // MARK: - Private
    private let stream: InputStream
    private var stringBuffer = Data()

    var length = 0

    private var string = "" {
        didSet {
            nextChar = nil
            length = string.count
        }
    }
    private let validFieldCharacters: CharacterSet

    private var nextIndex = 0 {
        didSet {
            nextChar = nil
        }
    }

    private var fieldIndex = 0
    private var fieldStart: String.Index?
    private var sanitizedField = ""

    private var delimiter: Character

    private var nextChar: Character?

    private var error: Error?

    private var currentRecord = 0

    public private(set) var canceled = false

    private func sniffEncoding() {

        var encoding = streamEncoding

        var bytes = [UInt8](repeating: 0, count: CHUNK_SIZE)
        let readLength = stream.read(&bytes, maxLength: CHUNK_SIZE)

        if readLength > 0 && readLength <= CHUNK_SIZE {
            stringBuffer.append(&bytes, count: readLength)

            totalBytesRead = totalBytesRead + readLength

            var bomLength = 0;

            if readLength > 3 && bytes[0] == 0x00 && bytes[1] == 0x00 && bytes[2] == 0xFE && bytes[3] == 0xFF {
                encoding = .utf32BigEndian
                bomLength = 4;
            } else if (readLength > 3 && bytes[0] == 0xFF && bytes[1] == 0xFE && bytes[2] == 0x00 && bytes[3] == 0x00) {
                encoding = .utf32LittleEndian
                bomLength = 4;
            } else if (readLength > 3 && bytes[0] == 0x1B && bytes[1] == 0x24 && bytes[2] == 0x29 && bytes[3] == 0x43) {
                encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.ISO_2022_KR.rawValue)))
                bomLength = 4;
            } else if (readLength > 1 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
                encoding = .utf16BigEndian
                bomLength = 2;
            } else if (readLength > 1 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
                encoding = .utf16LittleEndian
                bomLength = 2;
            } else if (readLength > 2 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
                encoding = .utf8
                bomLength = 3;
            } else {
                var bufferAsUTF8: String?

                for triedLength in 0..<4 {
                    bufferAsUTF8 = String(data: Data(bytes[0..<(readLength - triedLength)]), encoding: .utf8)
                    if (bufferAsUTF8 != nil) {
                        break;
                    }
                }

                if (bufferAsUTF8 != nil) {
                    encoding = .utf8
                } else {
                    print("unable to determine stream encoding; assuming MacOSRoman");
                    encoding = .macOSRoman
                }
            }

            if bomLength > 0 {
                stringBuffer.removeSubrange(0..<bomLength)
            }
        }
        streamEncoding = encoding;
    }

    private var tmpBuffer = [UInt8](repeating: 0, count: CHUNK_SIZE)

    private func loadMoreIfNecessary() {

        if nextIndex + 10 > length && stream.hasBytesAvailable {
            let readLength = stream.read(&tmpBuffer, maxLength: CHUNK_SIZE)

            if readLength > 0 {
                stringBuffer.append(contentsOf: tmpBuffer[0..<readLength])
                totalBytesRead += readLength

                if !stringBuffer.isEmpty {

                    var readLength = stringBuffer.count
                    while readLength > 0 {

                        if let readString = String(bytes: stringBuffer[0..<readLength], encoding: streamEncoding) {
                            string.append(readString)
                            break
                        } else {
                            readLength -= 1
                        }
                    }
                    if readLength == stringBuffer.count {
                        stringBuffer.removeAll(keepingCapacity: true)
                    } else {
                        stringBuffer.removeSubrange(0..<readLength)
                    }
                }
            }
        }

    }

    private func advance() {
        loadMoreIfNecessary()
        nextIndex += 1
    }


    private func peekCharacter(after: Int = 0) -> Character {
        loadMoreIfNecessary()
        if (nextIndex + after) >= length {
            return NULLCHAR
        }
        switch after {
        case 0:
            if let char = nextChar {
                return char
            }
            nextChar = string[string.index(string.startIndex, offsetBy: nextIndex)]
            if nextChar == NULLCHAR {
                
            }
            return nextChar!
        default:
            return string[string.index(string.startIndex, offsetBy: nextIndex + after)]
        }
    }

    private func parseRecord() -> Bool {
        while peekCharacter() == OCTOTHORPE && recognizesComments {
            _ = parseComment()
        }

        if peekCharacter() != NULLCHAR {
            autoreleasepool {
                beginRecord()
                while !canceled && parseField() && parseDelimiter() { }
                endRecord()
            }
        }

        return !canceled && parseNewline() && error == nil && peekCharacter() != NULLCHAR
    }

    private func beginRecord() {
        guard !canceled else { return }
        fieldIndex = 0
        currentRecord += 1
        delegate?.parser?(self, didBeginLine: currentRecord)
    }

    private func endRecord() {
        guard !canceled else { return }
        delegate?.parser?(self, didEndLine: currentRecord)
    }

    private func parseField() -> Bool {
        guard !canceled else { return false }
        var parsedField = false
        beginField()

        parseFieldWhitespace()

        if peekCharacter() == DOUBLE_QUOTE {
            parsedField = parseEscapedField()
        } else if recognizesLeadingEqualSign && peekCharacter() == EQUAL && peekCharacter(after: 1) == DOUBLE_QUOTE {
            advance()
            parsedField = parseEscapedField()
        } else {
            parsedField = parseUnescapedField()
            if trimsWhitespace {
                sanitizedField = sanitizedField.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if parsedField {
            parseFieldWhitespace()
            endField()
        }
        return parsedField
    }

    private func beginField() {
        guard !canceled else { return }
        sanitizedField = ""
        fieldStart = string.index(string.startIndex, offsetBy: nextIndex)
    }

    private func parseFieldWhitespace() {
        let whitespace = NSCharacterSet.whitespaces
        while peekCharacter() != NULLCHAR && whitespace.contains(peekCharacter().unicodeScalars.first!) && peekCharacter() != delimiter {
            if !trimsWhitespace {
                sanitizedField += "\(peekCharacter())"
                // if we're sanitizing fields, then these characters would be stripped (because they're not appended to sanitizedField)
            }
            advance()
        }
    }

    private func parseEscapedField() -> Bool {
        advance()
        let newlines = CharacterSet.newlines
        var isBackslashEscaped = false
        while true {
            let next = peekCharacter()
            if next == NULLCHAR {
                break
            }

            if !isBackslashEscaped {
                if next == BACKSLASH && recognizesBackslashesAsEscapes {
                    isBackslashEscaped = true
                    advance()
                } else if validFieldCharacters.contains(next.unicodeScalars.first!) || newlines.contains(next.unicodeScalars.first!) || next == delimiter {
                    sanitizedField += String(next)
                    advance()
                } else if next == DOUBLE_QUOTE && peekCharacter(after: 1) == DOUBLE_QUOTE {
                    sanitizedField += String(next)
                    advance()
                    advance()
                } else {
                    break
                }

            } else {
                sanitizedField += String(next)
                isBackslashEscaped = false
                advance()
            }
        }

        if peekCharacter() == DOUBLE_QUOTE {
            advance()
            return true
        }

        return false

    }

    private func parseUnescapedField() -> Bool {
        let newlines = CharacterSet.newlines
        var isBackslashEscaped = false
        while true {
            let next = peekCharacter()
            guard next != NULLCHAR else { break }

            if !isBackslashEscaped {
                if next == BACKSLASH && recognizesBackslashesAsEscapes {
                    isBackslashEscaped = true
                    advance()
                } else if newlines.contains(next.unicodeScalars.first!) || next == delimiter {
                    break
                } else {
                    sanitizedField += String(next)
                    advance()
                }

            } else {
                sanitizedField += String(next)
                isBackslashEscaped = false
                advance()
            }
        }
        return true

    }

    private func endField() {
        guard !canceled else { return }

        guard let start = fieldStart else { return }

        let end = string.index(string.startIndex, offsetBy: nextIndex)
        let range = start..<end
        var field: String
        if sanitizesFields {
            field = sanitizedField
        } else {

            field = String(string[range])
            if trimsWhitespace {
                field = field.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        delegate?.parser?(self, didReadField: field, at: fieldIndex)
        
        string.removeSubrange(string.startIndex..<end)
        nextIndex = 0
        fieldIndex += 1
    }


    private func parseDelimiter() -> Bool {
        let next = peekCharacter()
        if next == delimiter {
            advance()
            return true
        }
        if next != NULLCHAR && !CharacterSet.newlines.contains(String(next).unicodeScalars.first!) {
            print("unexpected delimiter, expected:\(delimiter) but got:\(next)")
            error = CSVError.invalidFormat
        }
        return false
    }

    private func parseNewline() -> Bool {
        guard !canceled else { return false }
        var charCount = 0
        let newLineSet = CharacterSet.newlines
        while newLineSet.contains(peekCharacter().unicodeScalars.first!) {
            charCount += 1
            advance()
        }
        return charCount > 0
    }




    private func parseComment() -> Bool {
        advance() // consume the octothorpe
        let newlines = CharacterSet.newlines

        beginComment()
        var isBackslashEscaped = false
        while true {
            if !isBackslashEscaped {
                let next = peekCharacter()
                if next == BACKSLASH && recognizesBackslashesAsEscapes {
                    isBackslashEscaped = true
                    advance()
                } else if !newlines.contains(String(next).unicodeScalars.first!) && next != NULLCHAR {
                    advance()
                } else {
                    // it's a newline
                    break;
                }
            } else {
                isBackslashEscaped = true
                advance()
            }
        }
        endComment()
        return parseNewline()

    }

    private func beginComment() {
        guard !canceled else { return }

        fieldStart = string.index(string.startIndex, offsetBy: nextIndex)
    }

    private func endComment() {
        guard !canceled else { return }

        guard let start = fieldStart else {
            return
        }

        let end = string.index(string.startIndex, offsetBy: nextIndex)

        let range = start..<end
        let comment = string[range]
        delegate?.parser?(self, didReadComment: String(comment))
        string.removeSubrange(string.startIndex..<end)
        nextIndex = 0

    }

}
public struct CSVParserOptions: OptionSet {
    public let rawValue: UInt
    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }
    /// Allow backslash to escape special characters.
    /// If you specify this option, you may not use a backslash as the delimiter.
    public static let recognizesBackslashesAsEscapes = CSVParserOptions(rawValue: 1 << 0)

    /// Cleans the field before reporting it.
    public static let sanitizesFields = CSVParserOptions(rawValue: 1 << 1)

    /// Fields that begin with a "#" will be reported as comments.
    /// If you specify this option, you may not use an octothorpe as the delimiter.
    public static let recognizesComments = CSVParserOptions(rawValue: 1 << 2)

    /// Trims whitespace around a field.
    public static let trimsWhitespace = CSVParserOptions(rawValue: 1 << 3)

    /// Some delimited files contain fields that begin with a leading equal sign,
    /// to indicate that the contents should not be summarized or re-interpreted.
    /// (For example, to remove insignificant digits)
    /// If you specify this option, you may not use an equal sign as the delimiter.
    public static let recognizesLeadingEqualSign = CSVParserOptions(rawValue: 1 << 5)

}

extension String {

    public func CSVComponents() -> [[String]] {

        return components(separatedBy: COMMA)
    }

    public func CSVComponents( with options: CSVParserOptions) -> [[String]] {
        return (try? components(separatedBy: COMMA, options: options)) ?? []
    }

    public func components(separatedBy delimiter: Character) -> [[String]] {
        return (try? components(separatedBy:delimiter, options:[])) ?? []
    }

    public func components(separatedBy delimiter: Character,  options: CSVParserOptions) throws -> [[String]] {
        guard let csvData = data(using: .utf8) else {
            return []
        }
        let stream = InputStream(data: csvData)

        return try CSVParser.parse(inputStream: stream, options: options, delimiter: delimiter)
    }

    public func keyedComponents(separatedBy delimiter: Character,  options: CSVParserOptions) throws -> [[String: String]] {
        guard let csvData = data(using: .utf8) else {
            return []
        }
        let stream = InputStream(data: csvData)

        return try CSVParser.parseKeyed(inputStream: stream, options: options, delimiter: delimiter)
    }
}

fileprivate class CSVAggregator: ParserDelegate {
    var lines = [[String]]()

    var currentLine = [String]()
    var error: Error?
    func parser(_ parser: CSVParser, didBeginLine line: Int) {
        currentLine = [String]()
    }
    func parser(_ parser: CSVParser, didEndLine line: Int) {
        lines.append(currentLine)
    }
    func parser(_ parser: CSVParser, didReadField field: String, at index: Int) {
        currentLine.append(field)
    }
    func parser(_ parser: CSVParser, didFailWithError error: Error) {
        lines.removeAll()
        self.error = error
    }
}

fileprivate class CSVKeyedAggregator: ParserDelegate {

    var lines = [[String: String]]()
    var firstLine = [String]()
    var currentLine = [String]()
    var error: Error?

    func parser(_ parser: CSVParser, didEndLine line: Int) {
        if firstLine.isEmpty {
            firstLine = currentLine
        } else if currentLine.count == firstLine.count{
            let line = Dictionary<String, String>(uniqueKeysWithValues: zip(firstLine,currentLine))
            lines.append(line)
        } else {
            parser.cancelParsing()
            error = CSVError.incorrectNumberOfFields
        }
        currentLine.removeAll()

    }
    func parser(_ parser: CSVParser, didReadField field: String, at index: Int) {
        currentLine.append(field)
    }
    func parser(_ parser: CSVParser, didFailWithError error: Error) {
        lines.removeAll()
        self.error = error
    }
}

