//
//  CheatTextView.swift
//  Delta
//
//  Created by Riley Testut on 5/22/16.
//  Copyright © 2016 Riley Testut. All rights reserved.
//

import UIKit
import CoreText

import DeltaCore

import Roxas

private let CheatPrefixAttribute = "prefix"

class CheatTextView: UITextView
{
    var cheatFormat: CheatFormat? {
        didSet {
            self.updateAttributedFormat()
        }
    }
    
    @NSCopying private var attributedFormat: NSAttributedString?
    
    required init?(coder aDecoder: NSCoder)
    {
        super.init(coder: aDecoder)
        
        self.layoutManager.delegate = self
        
        self.textContainer.widthTracksTextView = false
        self.textContainer.heightTracksTextView = false
    }
}

extension CheatTextView
{
    override func layoutSubviews()
    {
        super.layoutSubviews()
        
        if let format = self.cheatFormat, font = self.font
        {
            let characterWidth = ("A" as NSString).sizeWithAttributes([NSFontAttributeName: font]).width

            let width = characterWidth * CGFloat(format.format.characters.count)
            self.textContainer.size = CGSize(width: width, height: 0)
        }
    }
}

private extension CheatTextView
{
    func updateAttributedFormat()
    {
        guard let format = self.cheatFormat?.format else
        {
            self.attributedFormat = nil
            return
        }
        
        let attributedFormat = NSMutableAttributedString()
        var prefixString: NSString? = nil
        
        let scanner = NSScanner(string: format)
        scanner.charactersToBeSkipped = nil
        
        while (!scanner.atEnd)
        {
            var string: NSString? = nil
            scanner.scanCharactersFromSet(NSCharacterSet.alphanumericCharacterSet(), intoString: &string)
            
            guard let scannedString = string where scannedString.length > 0 else { break }
            
            let attributedString = NSMutableAttributedString(string: scannedString as String)
            
            if let prefixString = prefixString where prefixString.length > 0
            {
                attributedString.addAttribute(CheatPrefixAttribute, value: prefixString, range: NSRange(location: 0, length: 1))
            }
            
            attributedFormat.appendAttributedString(attributedString)
            
            prefixString = nil
            scanner.scanUpToCharactersFromSet(NSCharacterSet.alphanumericCharacterSet(), intoString: &prefixString)
        }
        
        self.attributedFormat = attributedFormat
        
        rst_dispatch_sync_on_main_thread {
            self.setNeedsLayout()
            self.layoutIfNeeded()
            
            let range = NSRange(location: 0, length: (self.text as NSString).length)
            self.layoutManager.invalidateGlyphsForCharacterRange(range, changeInLength: 0, actualCharacterRange: nil)
            self.layoutManager.invalidateLayoutForCharacterRange(range, actualCharacterRange: nil)
            self.layoutManager.ensureGlyphsForCharacterRange(range)
            self.layoutManager.ensureLayoutForCharacterRange(range)
        }
    }
}

extension CheatTextView: NSLayoutManagerDelegate
{
    func layoutManager(layoutManager: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>, properties props: UnsafePointer<NSGlyphProperty>, characterIndexes charIndexes: UnsafePointer<Int>, font aFont: UIFont, forGlyphRange glyphRange: NSRange) -> Int
    {
        // Returning 0 = let the layoutManager do the normal logic
        guard let attributedFormat = self.attributedFormat else { return 0 }
        
        let glyphCount = glyphRange.length
        
        // Ensure the buffer is long enough to hold our additional glyphs
        // If we're only modifying one character, glyphCount * 2 = 2, which is not large enough if we're inserting multiple separator characters
        let bufferSize = max(attributedFormat.length + 1, glyphCount * 2)
        
        // Allocate our replacement buffers
        let glyphBuffer = UnsafeMutablePointer<CGGlyph>.alloc(bufferSize)
        let propertyBuffer = UnsafeMutablePointer<NSGlyphProperty>.alloc(bufferSize)
        let characterBuffer = UnsafeMutablePointer<Int>.alloc(bufferSize)
        
        var offset = 0
        
        for i in 0 ..< glyphCount
        {
            // The index the actual character maps to in the cheat format
            let characterIndex = charIndexes[i] % attributedFormat.length
            
            if let prefix = attributedFormat.attributesAtIndex(characterIndex, effectiveRange: nil)[CheatPrefixAttribute] as? String
            {
                // If there is a prefix string, we insert the glyphs (and associated properties/character indexes) first
                let prefixCount = prefix.characters.count
                
                for j in 0 ..< prefixCount
                {
                    characterBuffer[i + offset + j] = charIndexes[i]
                    propertyBuffer[i + offset + j] = props[i]
                    
                    // Prepend prefix character
                    var prefixCharacter = (prefix as NSString).characterAtIndex(0)
                    CTFontGetGlyphsForCharacters(aFont as CTFont, &prefixCharacter, glyphBuffer + (i + offset + j), 1)
                }
                
                offset += prefixCount
            }
            
            // Copy over the information from the original buffers
            characterBuffer[i + offset] = charIndexes[i]
            propertyBuffer[i + offset] = props[i]
            glyphBuffer[i + offset] = glyphs[i]
        }
        
        // Replace buffers with our own buffers, and ensure length takes into account any added glpyhs
        layoutManager.setGlyphs(glyphBuffer, properties: propertyBuffer, characterIndexes: characterBuffer, font: aFont, forGlyphRange: NSRange(location: glyphRange.location, length: glyphCount + offset))
        
        // Clean up memory
        characterBuffer.dealloc(bufferSize)
        propertyBuffer.dealloc(bufferSize)
        glyphBuffer.dealloc(bufferSize)
        
        // Return total number of glyphs
        return glyphCount + offset
    }
}