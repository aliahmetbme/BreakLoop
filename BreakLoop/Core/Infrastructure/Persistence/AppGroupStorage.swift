//
//  AppGroupStorage.swift
//  BreakLoop
//
//  Created by Ali ahmet Erdoğdu on 6.10.2026.
//

import Foundation
import FamilyControls

final class AppGroupStorage {
    
    static let suiteName = "group.com.aliahmeterdogdu.BreakLoop"
    
    private struct Keys {
        static let activitySelection = "activitySelection"
    }
    
    private let defaults: UserDefaults
    
    init() {
        guard let defaults = UserDefaults(
            suiteName: Self.suiteName
        ) else {
            fatalError("App Group storage could not be initialized.")
        }
        
        self.defaults = defaults
    }
    
    func save<T: Codable>(
        _ value: T,
        forKey key: String
    ) throws {
        let data = try JSONEncoder().encode(value)
        defaults.set(data, forKey: key)
    }
    
    func load<T: Codable>(
        _ type: T.Type,
        forKey key: String
    ) throws -> T? {
        guard let data = defaults.data(forKey: key) else {
            return nil
        }
        
        return try JSONDecoder().decode(
            type,
            from: data
        )
    }
    
    func remove(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
    
    func saveActivitySelection(
        _ selection: FamilyActivitySelection
    ) throws {
        try save (
            selection,
            forKey: Keys.activitySelection
        )
    }
    
    func loadActivitySelection()
            throws -> FamilyActivitySelection? {

            try load(
                FamilyActivitySelection.self,
                forKey: Keys.activitySelection
            )
        }
    
}
