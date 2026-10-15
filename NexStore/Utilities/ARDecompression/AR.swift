//
//  SwiftAR.swift
//  SwiftAR
//
//  Created by nekohaxx on 8/18/24.
//

import Foundation

class AR: NSObject {
	private var _data: Data
	
	init(with url: URL) throws {
		self._data = try Data(contentsOf: url)
		super.init()
	}
	
	func extract() async throws -> [ARFileModel] {
        guard _data.count >= 8 else {
            throw ARError.badArchive("File is too small")
        }
        
		if [UInt8](_data.subdata(in: 0..<8)) != [0x21, 0x3c, 0x61, 0x72, 0x63, 0x68, 0x3e, 0x0a] {
			throw ARError.badArchive("Invalid magic")
		}
		
		let data = _data.subdata(in: 8..<_data.endIndex)
		
		var offset = 0
		var files: [ARFileModel] = []
		while offset < data.count {
            guard offset + 60 <= data.count else { break }
            
			let fileInfo = try _getFileInfo(data, offset)
			files.append(fileInfo)
			offset += fileInfo.size + 60
			offset += offset % 2
		}
		return files
	}
	
	private func _getFileInfo(_ data: Data, _ offset: Int) throws -> ARFileModel {
		let sizeString = _removePadding(String(data: data.subdata(in: offset+48..<offset+48+10), encoding: .ascii) ?? "0")
        guard let size = Int(sizeString), size >= 0 else {
			throw ARError.badArchive("Invalid size")
		}
        
        guard offset + 60 + size <= data.count else {
            throw ARError.badArchive("File content truncated")
        }
		
		let name = _removePadding(String(data: data.subdata(in: offset..<offset+16), encoding: .ascii) ?? "")
		guard name != "" else {
			throw ARError.badArchive("Invalid name")
		}
        
        let modDateStr = _removePadding(String(data: data.subdata(in: offset+16..<offset+16+12), encoding: .ascii) ?? "0")
        let ownerIdStr = _removePadding(String(data: data.subdata(in: offset+28..<offset+28+6), encoding: .ascii) ?? "0")
        let groupIdStr = _removePadding(String(data: data.subdata(in: offset+34..<offset+34+6), encoding: .ascii) ?? "0")
        let modeStr = _removePadding(String(data: data.subdata(in: offset+40..<offset+40+8), encoding: .ascii) ?? "0")
		
		return ARFileModel(
			name: name,
			modificationDate: Date(timeIntervalSince1970: Double(modDateStr) ?? 0),
			ownerId: Int(ownerIdStr) ?? 0,
			groupId: Int(groupIdStr) ?? 0,
			mode: Int(modeStr) ?? 0,
			size: size,
			content: data.subdata(in: offset+60..<offset+60+size)
		)
	}
	
	private func _removePadding(_ paddedString: String) -> String {
        return paddedString.trimmingCharacters(in: .whitespacesAndNewlines)
	}
}

enum ARError: Error {
	case badArchive(String)
}
