//
//  MongoCollection.swift
//  swiftMongoDB
//
//  Created by Dan Appel on 8/20/15.
//  Copyright © 2015 Dan Appel. All rights reserved.
//

import Foundation
import mongo_c_driver

// MARK: - MongoCollection
public class MongoCollection {
    
    /// The raw MongoDB connection
    internal var connection: UnsafeMutablePointer<mongo>!

    /// The name of the database to which this collection belongs.
    internal var databaseName: String!

    
    /// The database identifier in the format Database.Collection
    internal var identifier: String {
        return "\(self.databaseName).\(self.name)"
    }

    /// The name of the collection.
    public var name: String
    
    /**
    Initializes the collection, but initialization is not complete until the collection is registered with a MongoDB instance.

    - parameter name: The name of the collection
    
    - returns: An unregistered MongoCollection instance.
    */
    public init(name: String) {
        self.name = name
    }

    /**
    Initializes a registered collection with a MongoDB connection and a collection name.
    
    - parameter name:  The name of the collection - the "Collection" in "Database.Collection"
    - parameter mongo: A connected instance of MongoDB.

    - returns: A registered MongoCollection instance.
    */
    public init(name: String, mongo: MongoDB) {

        self.name = name
        self.connection = mongo.connection!
        self.databaseName = mongo.db

        mongo.collections.insert(self)
    }
    
    /// A boolean value which returns true if the collection is registered to a MongoDB instance.
    public var isRegistered: Bool {

        if self.connection != nil && self.databaseName != nil {
            return true
        }
        
        return false
    }
    
    internal func cursor() -> MongoCursor {
        return MongoCursor(connection: self.connection, collection: self)
    }


    /**
    Inserts a document into the collection. The collection needs to be registered.
    
    - parameter document: The document (of type MongoDocument) that is to be inserted into the collection.
    
    - returns: The inserted document.
    */
    public func insert(document: MongoDocument) throws -> MongoDocument {

        if self.connection == nil {
            print("didn't register collection")
            
            throw MongoError.CollectionNotRegistered
        }

        let mwc = mongo_write_concern_alloc()
        mongo_insert(self.connection, self.identifier, document.BSONValue, mongo_write_concern_alloc())
        mongo_write_concern_dealloc(mwc)


        return document
    }


    /**
    Removes a document from the collection.

    - parameter query: The query which will be used to find the documents to remove.

    - returns: The query document data.
    */
    public func remove(query: DocumentData) throws -> DocumentData {

        if self.connection == nil {
            throw MongoError.CollectionNotRegistered
        }

        let queryBSON = bson_alloc()
        let mongoBSON = MongoBSON(data: query)
        mongoBSON.copyTo(queryBSON)
        
        let mwc = mongo_write_concern_alloc()
        mongo_remove(self.connection, self.identifier, queryBSON, mwc)
        
        return query
    }

    
    /**
    An enum describing the types of Mongo update functions that can be performed.
    
    - Basic:  Single replacement (finds one, replaces it with document).
    - Upsert: Single replacement, insert if no documents match.
    - Multi:  Multiple replacement (finds all, replaces them with document).
    */
    public enum UpdateType {
        case Basic
        case Upsert
        case Multi
    }
    
    /**
    Updates the documents matched by the with the given modifications.
    
    - parameter query:          The query in the form of DocumentData ( [String : Any] )
    - parameter modifications:  The modifications applied to the matched object(s). Also in the form of DocumentData.
    - parameter type:           The type of update to be performed. Valid options are .Basic, .Upsert, .Multi

    - returns: A MongoDocument instance created from the given document data.
    */
    public func update(query query: DocumentData, document: DocumentData, type: UpdateType) throws -> MongoDocument {

        if self.connection == nil {
            throw MongoError.CollectionNotRegistered
        }

        let queryBSON = MongoBSON(data: query)
        let dataBSON = MongoBSON(data: document)

        let queryBSONRaw = bson_alloc()
        let dataBSONRaw = bson_alloc()
        queryBSON.copyTo(queryBSONRaw)
        dataBSON.copyTo(dataBSONRaw)


        let updateType: UInt32
        switch type {
        case .Basic:
            updateType = MONGO_UPDATE_BASIC.rawValue
        case .Upsert:
            updateType = MONGO_UPDATE_UPSERT.rawValue
        case .Multi:
            updateType = MONGO_UPDATE_MULTI.rawValue
        }


        let mwc = mongo_write_concern_alloc()
        mongo_update(self.connection, self.identifier, queryBSONRaw, dataBSONRaw, Int32(updateType), mwc)
        
        return MongoDocument(data: document)

    }

    public func update(query query: DocumentData, document: MongoDocument, type: UpdateType) throws -> MongoDocument {
        
        do {
            let result = try self.update(query: query, document: document.data, type: type)
            return result
        } catch {
            throw error
        }
    }

    public func update(id id: String, document: MongoDocument, type: UpdateType) throws -> MongoDocument {
        
        do {
            let result = try self.update(query: ["_id" : id], document: document.data, type: type)
            return result
        } catch {
            throw error
        }
    }

    public func update(id id: String, document: DocumentData, type: UpdateType) throws -> MongoDocument {
        
        do {
            let result = try self.update(query: ["_id" : id], document: document, type: type)
            return result
        } catch {
            throw error
        }
    }

    /**
    Queries for a single document matching the given query.
    
    - parameter queryData: A [String:AnyObject] query (can be nil) by which the document will be matched.
    
    - returns: The matched document.
    */
    public func findOne(queryData: DocumentData? = nil) throws -> MongoDocument {
        
        if self.connection == nil {
            
            throw MongoError.CollectionNotRegistered
        }

        let cursor = self.cursor()

        // refer to find() for an explanation of this snippet
        if let queryData = queryData {
            
            let mongoBSON = MongoBSON(data: queryData)
            
            let query = bson_alloc()
            mongoBSON.copyTo(query)
            
            cursor.query = query
        }
        
        if cursor.nextIsOk {
            
            return cursor.current
        }
  
        throw MongoError.NoDocumentsMatched
    }

    /**
    Queries for documents with the matching object id.
    
    - parameter id: The object id by which documents will be queried.
    
    - returns: A single matched document.
    */
    public func findOne(id id: String) throws -> MongoDocument {

        do {
            let result = try self.findOne(["_id" : id])
            return result
        } catch {
            throw error
        }
    }
    
    public func find(queryData: DocumentData? = nil) throws -> [MongoDocument] {
        
        if self.connection == nil {
            
            throw MongoError.CollectionNotRegistered
        }
        
        
        let cursor = self.cursor()
        
        // if query isn't blank (should be acceptable to not have query)
        if let queryData = queryData {
            
            // parse the query data into bson
            let mongoBSON = MongoBSON(data: queryData)
            
            let query = bson_alloc()
            mongoBSON.copyTo(query)
            // this copy step is required for whatever reason - without it everything breaks
            
            // cursor.query has a didSet where it gets bound to the actual cursor properly
            cursor.query = query
        }


        var results: [MongoDocument] = []
        
        var lastID: String = ""
        // loops through all the query results, appends them to array
        while cursor.nextIsOk {//mongo_cursor_next(cursor.cursor) == MONGO_OK {//cursor.nextIsOk && counter < max {

            let cur = cursor.current

            if let curID = cur.id {

                if curID == lastID {
                    break
                }
                
                lastID = curID
            }

            results.append(cur)
            
//            // need this otherwise is goes into an infinite loop (needs debugging to figure out why)
//            mongo_cursor_next(cursor.cursor)
        }
        
        return results
    }
    
    /**
    Queries for documents matching the given object id. It will return an array although it is theoretically impossible for the array length to be more than one.
    
    - parameter id: the object ID string by which documents will be matched.
    
    - returns: An array of matched documents.
    */
    public func find(id id: String) throws -> [MongoDocument] {
        
        
        do {
            let result = try self.find(["_id" : id])
            return result
        } catch {
            throw error
        }
    }
}

extension MongoCollection: Hashable {
    public var hashValue: Int {
        return self.name.hashValue
    }
}

public func == (lhs: MongoCollection, rhs: MongoCollection) -> Bool {
    return lhs.name == rhs.name
}
extension MongoCollection: Equatable {}
