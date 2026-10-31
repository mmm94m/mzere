//
//  SourcesViewModel.swift
//  Feather
//
//  Created by samara on 30.04.2025.
//

import Foundation
import AltSourceKit
import SwiftUI
import NimbleJSON

// MARK: - Class
final class SourcesViewModel: ObservableObject {
	static let shared = SourcesViewModel()
	
	typealias RepositoryDataHandler = Result<ASRepository, Error>
	
	private let _dataService = NBFetchService()
	
	var isFinished = true
	@Published var sources: [AltSource: ASRepository] = [:]
	
	func fetchSources(_ sources: FetchedResults<AltSource>, refresh: Bool = false, batchSize: Int = 4) async {
		guard isFinished else { return }
		
		// خوێندنەوەی تایبەتمەندییەکانی CoreData دەبێت سەدا سەد لەسەر Main Thread بێت
		let (shouldReturn, validSources) = await MainActor.run { () -> (Bool, [(AltSource, URL)]) in
			if !refresh, sources.allSatisfy({ self.sources[$0] != nil }) { 
				return (true, []) 
			}
			
			var extracted: [(AltSource, URL)] = []
			for source in sources {
				if let url = source.sourceURL {
					extracted.append((source, url))
				}
			}
			return (false, extracted)
		}
		
		if shouldReturn { return }
		
		isFinished = false
		defer { isFinished = true }
		
		await MainActor.run {
			self.sources = [:]
		}
		
		for startIndex in stride(from: 0, to: validSources.count, by: batchSize) {
			let endIndex = min(startIndex + batchSize, validSources.count)
			let batch = validSources[startIndex..<endIndex]
			
			let batchResults = await withTaskGroup(of: (AltSource, ASRepository?).self, returning: [AltSource: ASRepository].self) { group in
				for item in batch {
					group.addTask {
						// لێرەدا item.1 بریتییە لە URLـەکە کە بە سەلامەتی دەرهێنراوە
						return await withCheckedContinuation { continuation in
							self._dataService.fetch(from: item.1) { (result: RepositoryDataHandler) in
								switch result {
								case .success(let repo):
									continuation.resume(returning: (item.0, repo))
								case .failure(_):
									continuation.resume(returning: (item.0, nil))
								}
							}
						}
					}
				}
				
				var results = [AltSource: ASRepository]()
				for await (source, repo) in group {
					if let repo {
						results[source] = repo
					}
				}
				return results
			}
			
			await MainActor.run {
				for (source, repo) in batchResults {
					self.sources[source] = repo
				}
			}
		}
	}
}
