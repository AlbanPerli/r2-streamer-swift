//
//  RDEpubParser.swift
//  R2Streamer
//
//  Created by Olivier Körner on 08/12/2016.
//  Copyright © 2016 Readium. All rights reserved.
//

import Foundation
import AEXML


/**
 
 Errors thrown during the parsing of the EPUB

 - wrongMimeType: The mimetype file is missing or its content differs from `application/epub+zip`.
 - missingFile: A file is missing from the container.
 - xmlParse: An XML parsing error occurred.
 - missingElement: An XML element is missing.
 
*/
enum RDEpubParserError: Error {
    
    case wrongMimeType
    
    /// A file is missing from the container at relative path **path**.
    case missingFile(path: String)
    
    /**
        An XML parsing error occurred.
     
        - parameter underlyingError: The XML error thrown by the XML parser.
    */
    case xmlParse(underlyingError: Error)
    case missingElement(msg: String)
}


/**

 An EPUB container parser that extracts the information from the relevant files
 and builds an `RDPublication` instance with it.

 - It checks for a `mimetype` file with the proper contents.
 - It parses `container.xml` to look for the default rendition.
 - It parses the OPF file of the default rendition for the metadata, the assets and the spine.
 
*/
class RDEpubParser {
    
    /// The EPUB container to parse.
    var container: RDContainer
    
    /// The path to the default package document (OPF) to parse.
    var rootFile: String?
    
    /// The publication resulting from the parsing, if it is successful.
    var publication: RDPublication?
    
    /// The EPUB specification version to which the publication conforms.
    var epubVersion: Int?
    
    // TODO: multiple renditions
    // TODO: media overlays
    // TODO: TOC, LOI, etc.
    // TODO: encryption info
    
    /**
     
     The `RDEpubParser` is initialized with a `RDContainer`, through which it can access
     to the files in the EPUB container.

     - parameter container: a `RDContainer` instance.
     
    */
    init(container: RDContainer) {
        self.container = container
    }
    
    /**
     
     Parses the EPUB container files and builds a `RDPublication` representation.

     - returns: the resulting publication or nil.
     - throws:
        `RDEpubParserError.wrongMimeType`, 
        `RDEpubParserError.xmlParse`, 
        `RDEpubParserError.missingFile`
     
    */
    func parse() throws -> RDPublication? {
        if isMimeTypeValid() {
            try parseContainer()
            publication = try parseOPF(rootFile!)
        } else {
            throw RDEpubParserError.wrongMimeType
        }
        return publication
    }
    
    /** 
     
     Checks if the mimetype file is present and contains `application/epub+zip`.
    
     - returns: boolean result of the check
     
    */
    func isMimeTypeValid() -> Bool {
        if let mimeTypeData = try? container.data(relativePath: "mimetype") {
            let mimetype = String(data: mimeTypeData!, encoding: .ascii)
            return (mimetype == "application/epub+zip")
        }
        return false
    }
    
    /** 
     
     Parses the container.xml file of the container.
     It extracts the root file (the default one for now, not handling multiple renditions).
     
     - throws: `RDEpubParserError.xmlParse`, `RDEpubParserError.missingFile`
     
    */
    func parseContainer() throws {
        let containerPath = "META-INF/container.xml"
        guard let containerData = try container.data(relativePath: containerPath) else {
            throw RDEpubParserError.missingFile(path: containerPath)
        }
        
        var containerXml: AEXMLDocument
        do {
            containerXml = try AEXMLDocument(xml: containerData)
        }
        catch {
            throw RDEpubParserError.xmlParse(underlyingError: error)
        }

        // Look for the first `<roofile>` element
        let rootFileElement = containerXml.root["rootfiles"]["rootfile"]
        if let p = rootFileElement.attributes["full-path"] {
            rootFile = p
        } else {
            throw RDEpubParserError.missingElement(msg: "Missing rootfile element in container.xml")
        }
        
        // Get the specifications version the EPUB conforms to
        if let v = rootFileElement.attributes["version"] {
            epubVersion = Int(v)
        }
        
    }

    /** 
     
     Parses a OPF package document in the container.

     - parameter path: The relative path to OPF package file
 
     - returns: The optional publication resulting from the parsing.
     - throws: `RDEpubParserError.xmlParse`, `RDEpubParserError.missingFile`
     
    */
    func parseOPF(_ path: String) throws -> RDPublication? {
        // Get OPF document data from the container
        guard let data = try container.data(relativePath: rootFile!) else {
            throw RDEpubParserError.missingFile(path: rootFile!)
        }
        
        // Create an XML document from the data
        var doc: AEXMLDocument
        do {
            doc = try AEXMLDocument(xml: data)
        } catch {
            throw RDEpubParserError.xmlParse(underlyingError: error)
        }
        
        // Get EPUB version from <package> element if it was not set from container
        if epubVersion == nil {
            if let v = doc.root.attributes["version"] {
                epubVersion = Int(v)
            }
        }
        
        publication = RDPublication()
        publication!.internalData["type"] = "epub"
        publication!.internalData["rootfile"] = rootFile
        
        // Add self to links
        // MARK: we don't know the self URL here
        //publication!.links.append(RDLink(href: "TODO", typeLink: "application/webpub+json", rel: "self"))
        
        // Get the metadata from the <metadata> element
        let metadata = RDMetadata()
        
        // Get the main title
        metadata.title = parseMainTitle(doc)
        
        // Get the publication unique identifier
        metadata.identifier = parseUniqueIdentifier(doc)
        
        // Get the description
        if let desc = doc.root["metadata"]["dc:description"].value {
            metadata.description = desc
        }
        
        // TODO: modified date
        // TODO: subjects
        
        // Get the languages
        if let languages = doc.root["metadata"]["dc:language"].all {
            metadata.languages = languages.map { return $0.string }
        }
        
        // Get the rights 
        if let rights = doc.root["metadata"]["dc:rights"].all {
            metadata.rights = rights.map({ return $0.string }).joined(separator: " ")
        }
        
        // Get the publishers
        if let publishers = doc.root["metadata"]["dc:publisher"].all {
            for pub in publishers {
                metadata.publishers.append(RDContributor(name: pub.string))
            }
        }
        
        // Get the authors
        if let creators = doc.root["metadata"]["dc:creator"].all {
            for c in creators {
                parseContributor(c, fromDocument: doc, toMetadata: metadata)
            }
        }
        
        // Get the contributors
        if let contributors = doc.root["metadata"]["dc:contributor"].all {
            for c in contributors {
                parseContributor(c, fromDocument: doc, toMetadata: metadata)
            }
        }
        
        // Get the rendition properties
        if let renditionLayouts = doc.root["metadata"]["meta"].all(withAttributes: ["property" : "rendition:layout"]) {
            if renditionLayouts.count > 0 {
                metadata.rendition.layout = RDRenditionLayout(rawValue: renditionLayouts[0].string)
            }
        }
        if let renditionFlows = doc.root["metadata"]["meta"].all(withAttributes: ["property" : "rendition:flow"]) {
            if renditionFlows.count > 0 {
                metadata.rendition.flow = RDRenditionFlow(rawValue: renditionFlows[0].string)
            }
        }
        if let renditionOrientations = doc.root["metadata"]["meta"].all(withAttributes: ["property" : "rendition:orientation"]) {
            if renditionOrientations.count > 0 {
                metadata.rendition.orientation = RDRenditionOrientation(rawValue: renditionOrientations[0].string)
            }
        }
        if let renditionSpreads = doc.root["metadata"]["meta"].all(withAttributes: ["property" : "rendition:spread"]) {
            if renditionSpreads.count > 0 {
                metadata.rendition.spread = RDRenditionSpread(rawValue: renditionSpreads[0].string)
            }
        }
        if let renditionViewports = doc.root["metadata"]["meta"].all(withAttributes: ["property" : "rendition:viewport"]) {
            if renditionViewports.count > 0 {
                metadata.rendition.viewport = renditionViewports[0].string
            }
        }
                
        // Get the page progression direction
        if let dir = doc.root["spine"].attributes["page-progression-direction"] {
            metadata.direction = dir
        }
        
        publication!.metadata = metadata
        
        // Look for the manifest item id of the cover
        var coverId: String?
        if let coverMetas = doc.root["metadata"]["meta"].all(withAttributes: ["name" : "cover"]) {
            coverId = coverMetas.first?.string
        }
        
        parseSpineAndResources(fromDocument: doc, toPublication: publication!, coverItemId: coverId)
        
        return publication
    }
    
    /**
    
     Get the main title of the publication
 
     - parameter doc: The OPF XML document to parse
 
     - returns: The title if it was found, else `nil`
 
    */
    func parseMainTitle(_ doc: AEXMLDocument) -> String? {
        // Return if there isn't any `<dc:title>` element
        guard let titles = doc.root["metadata"]["dc:title"].all else {
            return nil
        }
        
        // If there's more than one, look for the `main` one as defined by `refines`
        if titles.count > 1 && epubVersion == 3 {
            let mainTitles = titles.filter { (element: AEXMLElement) in
                guard let eid = element.attributes["id"] else {
                    return false
                }
                let metas = doc.root["metadata"]["meta"].all(withAttributes: ["property": "title-type", "refines": "#" + eid])
                if let mainMetas = metas?.filter({ $0.string == "main" }) {
                    return mainMetas.count > 0
                }
                return false
            }
            if mainTitles.count > 0 {
                return mainTitles.first!.string
            }
        }
        
        // As a fallback and default, return the first `<dc:title>` content
        return doc.root["metadata"]["dc:title"].string
    }
    
    /**
     
     Get the unique identifer of the publication
     
     - parameter doc: The OPF XML document to parse
     
     - returns: The identifier if it was found, else `nil`
     
     */
    func parseUniqueIdentifier(_ doc: AEXMLDocument) -> String? {
        // Look for `<dc:identifier>` elements
        guard let identifiers = doc.root["metadata"]["dc:identifier"].all else {
            return nil
        }
        
        // Get the one defined as unique by the `<package>` attribute `unique-identifier`
        if identifiers.count > 1 {
            if let uniqueId = doc.root.attributes["unique-identifier"] {
                let uniqueIdentifiers = identifiers.filter { $0.attributes["id"] == uniqueId }
                if uniqueIdentifiers.count > 0 {
                    return uniqueIdentifiers.first!.string
                }
            }
        }
        
        // As a fallback and default, return the first `<dc:identifier>` content
        return doc.root["metadata"]["dc:identifier"].string
    }
    
    /**
     
     Builds a `RDContributor` instance from a `<dc:creator>` or `<dc:contributor>` element.

     - parameter element: The XML element to parse.
     - parameter fromDocument: The OPF XML document being parsed (necessary to look for `refines`).
 
     - returns: The contributor instance filled with its name and optionally its `role` and `sortAs` attributes.
     
    */
    func createContributorFromElement(element: AEXMLElement, fromDocument doc: AEXMLDocument) -> RDContributor {
        let contributor = RDContributor(name: element.string)
        
        // Get role from role attribute
        if let role = element.attributes["opf:role"] {
            contributor.role = role
        }
        
        // Get sort name from file-as attribute
        if let sortAs = element.attributes["opf:file-as"] {
            contributor.sortAs = sortAs
        }
        
        // Look up for possible meta refines for role
        let eid = element.attributes["id"]
        if eid != nil && epubVersion == 3 {
            if let metas = doc.root["metadata"]["meta"].all(withAttributes: ["property": "role", "refines": "#" + eid!]) {
                if metas.count > 0 {
                    let role = metas.first!.string
                    contributor.role = role
                }
            }
        }
        
        return contributor
    }
    
    /**
 
     Parse a `creator` or `contributor` element from the OPF XML document, then builds and adds a RDContributor
     to the metadata, to an array according to its role (authors, translators, etc.)
 
     - parameter element: The XML element to parse
     - parameter doc: The OPF XML document being parsed
     - parameter metadata: The metadata to which to add the contributor
 
    */
    func parseContributor(_ element: AEXMLElement, fromDocument doc: AEXMLDocument, toMetadata metadata: RDMetadata) {
        let contributor = createContributorFromElement(element: element, fromDocument: doc)
        
        // Add the contributor to the proper property according to the its `role`
        if let role = contributor.role {
            switch role {
            case "aut":
                metadata.authors.append(contributor)
            case "trl":
                metadata.translators.append(contributor)
            case "art":
                metadata.artists.append(contributor)
            case "edt":
                metadata.editors.append(contributor)
            case "ill":
                metadata.illustrators.append(contributor)
            case "clr":
                metadata.colorists.append(contributor)
            case "nrt":
                metadata.narrators.append(contributor)
            case "pbl":
                metadata.publishers.append(contributor)
            default:
                metadata.contributors.append(contributor)
            }
        } else {
            // No role, so add the creators to the authors and the others to the contributors
            if element.name == "dc:creator" {
                metadata.authors.append(contributor)
            } else {
                metadata.contributors.append(contributor)
            }
        }
    }
    
    /**
     
     Parses the manifest and spine elements to build the document's spine and it resources list.
     
     - parameter doc: The OPF XML document being parsed.
     - parameter publication: The publication whose spine and resources will be built.
     - parameter coverItemId: The id of the cover item in the manifest.
     
    */
    func parseSpineAndResources(fromDocument doc: AEXMLDocument, toPublication publication: RDPublication, coverItemId: String?) {
        // Create a dictionary for all the manifest items keyed by their id
        var manifestLinks = [String: RDLink]()
        
        // Find all the manifest items
        if let manifestItems = doc.root["manifest"]["item"].all {
            
            // Create an RDLink for each of them
            for item in manifestItems {
                
                // Build a link for the manifest item
                let link = RDLink()
                link.href = item.attributes["href"]
                link.typeLink = item.attributes["media-type"]
                
                // Look for properties
                if let propAttr = item.attributes["properties"] {
                    let props = propAttr.components(separatedBy: CharacterSet.whitespaces)
                    if props.contains("nav") {
                        link.rel.append("contents")
                    }
                    
                    // If it's a cover, set the rel to cover and add the link to `links`
                    if props.contains("cover-image") {
                        link.rel.append("cover")
                        publication.links.append(link)
                    }
                    
                    // TODO: rendition properties
                }
                
                // Add it to the manifest items dict if it has an id
                if let id = item.attributes["id"] {
                    
                    // If it's the cover's item id, set the rel to cover and add the link to `links`
                    if id == coverItemId {
                        link.rel.append("cover")
                        publication.links.append(link)
                    }
                    
                    manifestLinks[id] = link
                } else {
                    // Manifest item MUST have an id, ignore it
                    NSLog("Manifest item has no \"id\" attribute")
                }
            }
        }
        
        // Parse the `<spine>` element children
        if let spineItems = doc.root["spine"]["itemref"].all {
            
            // For each spine item, look for the link in manifestLinks dictionary,
            // add it to the spine and remove it from manifestLinks.
            for item in spineItems {
                if let id = item.attributes["idref"] {
                    if let link = manifestLinks[id] {
                        // Found the link in the manifest items, add it to the spine
                        publication.spine.append(link)
                        
                        // Then remove it from the manifest
                        manifestLinks.removeValue(forKey: id)
                    }
                }
            }
        }
        
        // Those links that were not in the spine are the resources,
        // they've already been removed from the manifestLinks dictionary
        publication.resources = [RDLink](manifestLinks.values)
    }
    
}
