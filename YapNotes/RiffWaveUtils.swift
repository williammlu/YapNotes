import Foundation

func decodeWaveFile(_ url: URL) throws -> [Float] {
    let data = try Data(contentsOf: url)
    guard data.count > 44 else {
        return []
    }
    let strideSize = 2
    let startIndex = 44
    var floats = [Float]()
    var i = startIndex
    while i + strideSize <= data.count {
        let sampleData = data[i..<(i + strideSize)]
        let value = sampleData.withUnsafeBytes {
            Float(Int16(littleEndian: $0.load(as: Int16.self))) / 32767.0
        }
        floats.append(value)
        i += strideSize
    }
    return floats
}