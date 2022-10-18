//
//  ByteBuffer+Helpers.swift
//  
//
//  Created by Konstantin Gorshkov on 02.08.2022.
//

import Foundation
import NIOCore


extension ByteBuffer {

    static private let encodingConversionArrayCP866toWindows1251: [UInt8] = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 124, 125, 126, 127, 192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 202, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 215, 216, 217, 218, 219, 220, 221, 222, 223, 224, 225, 226, 227, 228, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 45, 45, 45, 166, 43, 166, 166, 172, 172, 166, 166, 172, 45, 45, 45, 172, 76, 43, 84, 43, 45, 43, 166, 166, 76, 227, 166, 84, 166, 61, 43, 166, 166, 84, 84, 76, 76, 45, 227, 43, 43, 45, 45, 45, 45, 166, 166, 45, 240, 241, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251, 252, 253, 254, 255, 168, 184, 170, 186, 175, 191, 161, 162, 176, 149, 183, 118, 185, 164, 166, 160]
    
    public mutating func convertFromCP866ToWindows1251 () {
        self.withUnsafeMutableReadableBytes { buf in
            for index in 0..<buf.count {
                buf[index] = Self.encodingConversionArrayCP866toWindows1251[Int(buf[index])]
            }
        }
    }
    
    public enum CSVTOJSONERROR: Error {
        case IncorrectFieldsCount
        case CantDecodeBufferWithSpecifiedEncoding
    }
    
    public func wrapToJSON (fields: [String], delimiter: Character = " ", encoding: String.Encoding = .utf8, extractField: String? = nil, allocator: ByteBufferAllocator) throws -> (ByteBuffer, String?) {
        guard let values = self.getString(at: 0, length: self.readableBytes, encoding: encoding)?.split(separator: delimiter) else { throw CSVTOJSONERROR.CantDecodeBufferWithSpecifiedEncoding }
        guard fields.count == values.count else { throw CSVTOJSONERROR.IncorrectFieldsCount }
        
        var extractedValue: String? = nil
        
        var fieldsLength = 0
        fields.forEach{ fieldsLength += $0.count }
        var newBuf = allocator.buffer(capacity: self.readableBytes + fieldsLength + fields.count * 10)
        
        try newBuf.writeString("{", encoding: encoding)
        
        for index in 0..<fields.count {
            try newBuf.writeString(" \"\(fields[index])\": \"\(values[index])\"\(index != fields.count - 1 ? ",": "")", encoding: encoding)
            if let extractField = extractField, extractField == fields[index] {
                extractedValue = String(values[index])
            }
        }
        
        try newBuf.writeString(" }", encoding: encoding)
        return (newBuf, extractedValue)
        
    }
    
    
    
    
    
    public func wrapToSSE (eventName: String? = nil, encoding: String.Encoding = .utf8, allocator: ByteBufferAllocator) -> ByteBuffer {
        var newBuf = allocator.buffer(capacity: self.readableBytes + 30)
        if let eventName = eventName { newBuf.writeString("event: \(eventName)\n") }
        newBuf.writeString("data: ")
        
        //  replace: '\'  -> '\\'
        let slashChar: UInt8 = Character("\\").asciiValue!
        if var tempBuf: [UInt8] = self.getBytes(at: 0, length: self.readableBytes), tempBuf.count > 0 {
            for index in (0..<tempBuf.count).reversed() {
                if tempBuf[index] == slashChar {
                    tempBuf.insert(slashChar, at: index)
                }
            }
            
            newBuf.setBytes(tempBuf, at: newBuf.writerIndex)
            newBuf.moveWriterIndex(forwardBy: tempBuf.count)
        }
             
        newBuf.writeString("\n\n")
        return newBuf
    }
    
    
}






