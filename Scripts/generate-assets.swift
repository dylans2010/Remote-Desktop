#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

// MARK: - Helper Functions

func savePNG(image: NSImage, targetSize: NSSize, to url: URL) {
    let resizedImage = NSImage(size: targetSize)
    resizedImage.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(origin: .zero, size: targetSize),
               from: NSRect(origin: .zero, size: image.size),
               operation: .copy,
               fraction: 1.0)
    resizedImage.unlockFocus()
    
    if let tiff = resizedImage.tiffRepresentation,
       let rep = NSBitmapImageRep(data: tiff),
       let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: url)
    }
}

// MARK: - iOS App Icon (Full-bleed square, modern plain backdrop, SF Symbol)

func createIOSIcon() -> NSImage {
    let size = NSSize(width: 1024, height: 1024)
    let image = NSImage(size: size)
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }
    
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    
    // Deep modern slate gradient
    let bgColors = [
        NSColor(red: 0.12, green: 0.15, blue: 0.22, alpha: 1.0).cgColor,
        NSColor(red: 0.05, green: 0.07, blue: 0.11, alpha: 1.0).cgColor
    ] as CFArray
    if let bgGrad = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(bgGrad, start: CGPoint(x: 512, y: 1024), end: CGPoint(x: 512, y: 0), options: [])
    }
    
    // Subtle modern radial luminance
    let auraColors = [
        NSColor(red: 0.22, green: 0.50, blue: 0.90, alpha: 0.35).cgColor,
        NSColor(red: 0.08, green: 0.15, blue: 0.30, alpha: 0.0).cgColor
    ] as CFArray
    if let auraGrad = CGGradient(colorsSpace: colorSpace, colors: auraColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(auraGrad,
                               startCenter: CGPoint(x: 512, y: 530), startRadius: 0,
                               endCenter: CGPoint(x: 512, y: 530), endRadius: 460,
                               options: [])
    }
    
    // SF Symbol: display.2
    let pConfig = NSImage.SymbolConfiguration(paletteColors: [
        NSColor(red: 0.96, green: 0.98, blue: 1.0, alpha: 1.0),
        NSColor(red: 0.18, green: 0.58, blue: 0.98, alpha: 1.0)
    ])
    let wConfig = NSImage.SymbolConfiguration(pointSize: 420, weight: .semibold)
    let conf = pConfig.applying(wConfig)
    
    if let symbol = NSImage(systemSymbolName: "display.2", accessibilityDescription: nil)?.withSymbolConfiguration(conf) {
        let symSize = symbol.size
        let symRect = CGRect(x: (1024 - symSize.width) / 2,
                             y: (1024 - symSize.height) / 2 - 10,
                             width: symSize.width,
                             height: symSize.height)
        
        // Soft drop shadow
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 24, color: NSColor.black.withAlphaComponent(0.45).cgColor)
        symbol.draw(in: symRect)
        ctx.restoreGState()
        
        symbol.draw(in: symRect)
    }
    
    image.unlockFocus()
    return image
}

// MARK: - macOS App Icon (Transparent canvas, continuous squircle, physical depth effects)

func createMacOSIcon() -> NSImage {
    let size = NSSize(width: 1024, height: 1024)
    let image = NSImage(size: size)
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }
    
    // Transparent canvas
    ctx.clear(CGRect(x: 0, y: 0, width: 1024, height: 1024))
    
    // Official macOS squircle geometry (824x824 centered in 1024x1024)
    let squircleRect = CGRect(x: 100, y: 100, width: 824, height: 824)
    let squirclePath = NSBezierPath(roundedRect: squircleRect, xRadius: 185, yRadius: 185)
    
    // Multi-tier realistic drop shadows
    // 1. Soft ambient floor shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -22), blur: 38, color: NSColor.black.withAlphaComponent(0.32).cgColor)
    NSColor.black.withAlphaComponent(0.2).setFill()
    squirclePath.fill()
    ctx.restoreGState()
    
    // 2. Key directional shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 16, color: NSColor.black.withAlphaComponent(0.40).cgColor)
    NSColor.black.withAlphaComponent(0.3).setFill()
    squirclePath.fill()
    ctx.restoreGState()
    
    // 3. Contact edge shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -3), blur: 5, color: NSColor.black.withAlphaComponent(0.45).cgColor)
    NSColor.black.withAlphaComponent(0.4).setFill()
    squirclePath.fill()
    ctx.restoreGState()
    
    // Clip inside squircle for surface textures & symbols
    ctx.saveGState()
    squirclePath.addClip()
    
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        NSColor(red: 0.12, green: 0.15, blue: 0.22, alpha: 1.0).cgColor,
        NSColor(red: 0.06, green: 0.08, blue: 0.12, alpha: 1.0).cgColor
    ] as CFArray
    if let bgGrad = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(bgGrad, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
    }
    
    // Subtle modern radial luminance
    let auraColors = [
        NSColor(red: 0.20, green: 0.45, blue: 0.85, alpha: 0.30).cgColor,
        NSColor(red: 0.10, green: 0.20, blue: 0.40, alpha: 0.0).cgColor
    ] as CFArray
    if let auraGrad = CGGradient(colorsSpace: colorSpace, colors: auraColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(auraGrad,
                               startCenter: CGPoint(x: 512, y: 550), startRadius: 0,
                               endCenter: CGPoint(x: 512, y: 550), endRadius: 380,
                               options: [])
    }
    
    // Inset chamfer / bevel rim highlight
    let innerBorderRect = squircleRect.insetBy(dx: 1.5, dy: 1.5)
    let innerBorderPath = NSBezierPath(roundedRect: innerBorderRect, xRadius: 183.5, yRadius: 183.5)
    ctx.saveGState()
    ctx.setLineWidth(2.0)
    ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.18).cgColor)
    innerBorderPath.stroke()
    ctx.restoreGState()
    
    // SF Symbol with elevated depth effects
    let pConfig = NSImage.SymbolConfiguration(paletteColors: [
        NSColor(red: 0.96, green: 0.98, blue: 1.0, alpha: 1.0),
        NSColor(red: 0.18, green: 0.58, blue: 0.98, alpha: 1.0)
    ])
    let wConfig = NSImage.SymbolConfiguration(pointSize: 370, weight: .semibold)
    let conf = pConfig.applying(wConfig)
    
    if let symbol = NSImage(systemSymbolName: "display.2", accessibilityDescription: nil)?.withSymbolConfiguration(conf) {
        let symSize = symbol.size
        let symRect = CGRect(x: (1024 - symSize.width) / 2,
                             y: (1024 - symSize.height) / 2 - 10,
                             width: symSize.width,
                             height: symSize.height)
        
        // Glyph cast shadow onto tile
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 24, color: NSColor.black.withAlphaComponent(0.60).cgColor)
        symbol.draw(in: symRect)
        ctx.restoreGState()
        
        // Second tighter contact shadow
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 8, color: NSColor.black.withAlphaComponent(0.50).cgColor)
        symbol.draw(in: symRect)
        ctx.restoreGState()
        
        // Crisp symbol on top
        symbol.draw(in: symRect)
    }
    
    ctx.restoreGState() // unclip
    
    // Subtle top border rim on squircle for glass chamfer
    ctx.saveGState()
    let rimPath = NSBezierPath(roundedRect: squircleRect, xRadius: 185, yRadius: 185)
    rimPath.lineWidth = 1.0
    NSColor(white: 1.0, alpha: 0.15).setStroke()
    rimPath.stroke()
    ctx.restoreGState()
    
    image.unlockFocus()
    return image
}

// MARK: - Styled DMG Background

func createDMGBackground() -> NSImage {
    let width: CGFloat = 660
    let height: CGFloat = 420
    let scale: CGFloat = 2.0 // High DPI Retina
    
    let size = NSSize(width: width * scale, height: height * scale)
    let image = NSImage(size: size)
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }
    
    ctx.scaleBy(x: scale, y: scale)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    
    // 1. Sleek modern gradient background
    let bgColors = [
        NSColor(red: 0.08, green: 0.11, blue: 0.17, alpha: 1.0).cgColor,
        NSColor(red: 0.04, green: 0.06, blue: 0.09, alpha: 1.0).cgColor
    ] as CFArray
    if let bgGrad = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(bgGrad, start: CGPoint(x: width / 2, y: height), end: CGPoint(x: width / 2, y: 0), options: [])
    }
    
    // 2. Subtle decorative glow behind App (left) and Applications (right)
    let leftCenter = CGPoint(x: 170, y: 205)
    let rightCenter = CGPoint(x: 490, y: 205)
    
    let glowColors = [
        NSColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 0.22).cgColor,
        NSColor(red: 0.0, green: 0.48, blue: 1.0, alpha: 0.0).cgColor
    ] as CFArray
    if let glowGrad = CGGradient(colorsSpace: colorSpace, colors: glowColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(glowGrad, startCenter: leftCenter, startRadius: 0, endCenter: leftCenter, endRadius: 130, options: [])
        ctx.drawRadialGradient(glowGrad, startCenter: rightCenter, startRadius: 0, endCenter: rightCenter, endRadius: 130, options: [])
    }
    
    // Subtle drop zones (rounded pedestals) under icons
    let dropPlateRectL = CGRect(x: 100, y: 135, width: 140, height: 140)
    let dropPlateRectR = CGRect(x: 420, y: 135, width: 140, height: 140)
    
    let platePathL = NSBezierPath(roundedRect: dropPlateRectL, xRadius: 28, yRadius: 28)
    let platePathR = NSBezierPath(roundedRect: dropPlateRectR, xRadius: 28, yRadius: 28)
    
    ctx.saveGState()
    ctx.setLineWidth(1.5)
    ctx.setStrokeColor(NSColor(white: 1.0, alpha: 0.08).cgColor)
    ctx.setFillColor(NSColor(white: 1.0, alpha: 0.03).cgColor)
    platePathL.fill()
    platePathL.stroke()
    platePathR.fill()
    platePathR.stroke()
    ctx.restoreGState()
    
    // 3. Header: App title and SF symbol
    let titleConfig = NSImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        .applying(NSImage.SymbolConfiguration(hierarchicalColor: NSColor(red: 0.20, green: 0.65, blue: 1.0, alpha: 1.0)))
    if let headerSymbol = NSImage(systemSymbolName: "display.2", accessibilityDescription: nil)?.withSymbolConfiguration(titleConfig) {
        let hSymRect = CGRect(x: 200, y: 352, width: headerSymbol.size.width, height: headerSymbol.size.height)
        headerSymbol.draw(in: hSymRect)
    }
    
    let titleText = "Remote Desktop for Mac"
    let titleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 20, weight: .bold),
        .foregroundColor: NSColor.white
    ]
    (titleText as NSString).draw(at: CGPoint(x: 245, y: 350), withAttributes: titleAttrs)
    
    let subtitleText = "Drag Remote Desktop into Applications to install"
    let subtitleAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
        .foregroundColor: NSColor(white: 0.70, alpha: 1.0)
    ]
    let subtitleSize = (subtitleText as NSString).size(withAttributes: subtitleAttrs)
    (subtitleText as NSString).draw(at: CGPoint(x: (width - subtitleSize.width) / 2, y: 326), withAttributes: subtitleAttrs)
    
    // 4. Center Arrow with SF Symbol pointing from App to Applications
    let arrowConfig = NSImage.SymbolConfiguration(pointSize: 42, weight: .bold)
        .applying(NSImage.SymbolConfiguration(hierarchicalColor: NSColor(red: 0.25, green: 0.70, blue: 1.0, alpha: 1.0)))
    if let arrowSymbol = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil)?.withSymbolConfiguration(arrowConfig) {
        let arrowRect = CGRect(x: (width - arrowSymbol.size.width) / 2,
                               y: 195,
                               width: arrowSymbol.size.width,
                               height: arrowSymbol.size.height)
        
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 0), blur: 18, color: NSColor(red: 0.0, green: 0.55, blue: 1.0, alpha: 0.65).cgColor)
        arrowSymbol.draw(in: arrowRect)
        ctx.restoreGState()
        
        arrowSymbol.draw(in: arrowRect)
    }
    
    // Secondary SF symbol badge
    let badgeText = "INSTALL"
    let badgeAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11, weight: .heavy),
        .foregroundColor: NSColor(red: 0.35, green: 0.75, blue: 1.0, alpha: 1.0)
    ]
    let badgeSize = (badgeText as NSString).size(withAttributes: badgeAttrs)
    let badgeRect = CGRect(x: (width - badgeSize.width - 24) / 2, y: 156, width: badgeSize.width + 24, height: 22)
    let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 11, yRadius: 11)
    
    ctx.saveGState()
    ctx.setFillColor(NSColor(red: 0.0, green: 0.45, blue: 1.0, alpha: 0.15).cgColor)
    ctx.setStrokeColor(NSColor(red: 0.0, green: 0.55, blue: 1.0, alpha: 0.35).cgColor)
    ctx.setLineWidth(1.0)
    badgePath.fill()
    badgePath.stroke()
    ctx.restoreGState()
    
    (badgeText as NSString).draw(at: CGPoint(x: (width - badgeSize.width) / 2, y: 159), withAttributes: badgeAttrs)
    
    let footerText = "Requires macOS 14.0 or later"
    let footerAttrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 11, weight: .regular),
        .foregroundColor: NSColor(white: 0.45, alpha: 1.0)
    ]
    let footerSize = (footerText as NSString).size(withAttributes: footerAttrs)
    (footerText as NSString).draw(at: CGPoint(x: (width - footerSize.width) / 2, y: 25), withAttributes: footerAttrs)
    
    image.unlockFocus()
    return image
}

// MARK: - Main Execution

let fileManager = FileManager.default
let currentDir = URL(fileURLWithPath: fileManager.currentDirectoryPath)

print("1. Generating iOS AppIcon variants...")
let iosIcon = createIOSIcon()
let iosIconDir = currentDir.appendingPathComponent("Sources/iOS/Resources/Assets.xcassets/AppIcon.appiconset")
let iosSizes: [(String, CGFloat)] = [
    ("AppIcon-1024.png", 1024),
    ("AppIcon-60@3x.png", 180),
    ("AppIcon-60@2x.png", 120),
    ("AppIcon-76@2x.png", 152),
    ("AppIcon-83.5@2x.png", 167),
    ("AppIcon-29@3x.png", 87),
    ("AppIcon-29@2x.png", 58),
    ("AppIcon-40@3x.png", 120),
    ("AppIcon-40@2x.png", 80)
]

for (name, size) in iosSizes {
    let url = iosIconDir.appendingPathComponent(name)
    savePNG(image: iosIcon, targetSize: NSSize(width: size, height: size), to: url)
    // Also save in Sources/iOS/Resources for direct bundle embedding
    let bundleUrl = currentDir.appendingPathComponent("Sources/iOS/Resources").appendingPathComponent(name)
    savePNG(image: iosIcon, targetSize: NSSize(width: size, height: size), to: bundleUrl)
}

let iosContentsJSON = """
{
  "images" : [
    {
      "idiom" : "universal",
      "platform" : "ios",
      "size" : "1024x1024",
      "filename" : "AppIcon-1024.png"
    },
    {
      "idiom" : "iphone",
      "size" : "60x60",
      "scale" : "2x",
      "filename" : "AppIcon-60@2x.png"
    },
    {
      "idiom" : "iphone",
      "size" : "60x60",
      "scale" : "3x",
      "filename" : "AppIcon-60@3x.png"
    },
    {
      "idiom" : "ipad",
      "size" : "76x76",
      "scale" : "2x",
      "filename" : "AppIcon-76@2x.png"
    },
    {
      "idiom" : "ipad",
      "size" : "83.5x83.5",
      "scale" : "2x",
      "filename" : "AppIcon-83.5@2x.png"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
try? iosContentsJSON.write(to: iosIconDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("   Done iOS AppIcon.")

print("2. Generating macOS AppIcon variants with depth effects...")
let macIcon = createMacOSIcon()
let macIconDir = currentDir.appendingPathComponent("Sources/macOS/Resources/Assets.xcassets/AppIcon.appiconset")

// Iconset directory for iconutil
let iconsetDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("AppIcon.iconset")
try? fileManager.removeItem(at: iconsetDir)
try? fileManager.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

let macIconsetMapping: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

for (name, size) in macIconsetMapping {
    let url = iconsetDir.appendingPathComponent(name)
    savePNG(image: macIcon, targetSize: NSSize(width: size, height: size), to: url)
    
    // Also save in macOS xcassets
    let xcUrl = macIconDir.appendingPathComponent(name)
    savePNG(image: macIcon, targetSize: NSSize(width: size, height: size), to: xcUrl)
}

let macContentsJSON = """
{
  "images" : [
    {
      "idiom" : "mac",
      "size" : "16x16",
      "scale" : "1x",
      "filename" : "icon_16x16.png"
    },
    {
      "idiom" : "mac",
      "size" : "16x16",
      "scale" : "2x",
      "filename" : "icon_16x16@2x.png"
    },
    {
      "idiom" : "mac",
      "size" : "32x32",
      "scale" : "1x",
      "filename" : "icon_32x32.png"
    },
    {
      "idiom" : "mac",
      "size" : "32x32",
      "scale" : "2x",
      "filename" : "icon_32x32@2x.png"
    },
    {
      "idiom" : "mac",
      "size" : "128x128",
      "scale" : "1x",
      "filename" : "icon_128x128.png"
    },
    {
      "idiom" : "mac",
      "size" : "128x128",
      "scale" : "2x",
      "filename" : "icon_128x128@2x.png"
    },
    {
      "idiom" : "mac",
      "size" : "256x256",
      "scale" : "1x",
      "filename" : "icon_256x256.png"
    },
    {
      "idiom" : "mac",
      "size" : "256x256",
      "scale" : "2x",
      "filename" : "icon_256x256@2x.png"
    },
    {
      "idiom" : "mac",
      "size" : "512x512",
      "scale" : "1x",
      "filename" : "icon_512x512.png"
    },
    {
      "idiom" : "mac",
      "size" : "512x512",
      "scale" : "2x",
      "filename" : "icon_512x512@2x.png"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
"""
try? macContentsJSON.write(to: macIconDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

// Create AppIcon.icns using iconutil
let icnsTarget = currentDir.appendingPathComponent("Sources/macOS/Resources/AppIcon.icns")
let volIconTarget = currentDir.appendingPathComponent("Scripts/assets/volume-icon.icns")
let iconutilTask = Process()
iconutilTask.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutilTask.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsTarget.path]
try? iconutilTask.run()
iconutilTask.waitUntilExit()

try? fileManager.copyItem(at: icnsTarget, to: volIconTarget)
print("   Done macOS AppIcon.icns.")

print("3. Generating Styled DMG Background...")
let dmgBg = createDMGBackground()
let dmgBgTarget = currentDir.appendingPathComponent("Scripts/assets/dmg-background.png")
if let tiff = dmgBg.tiffRepresentation,
   let rep = NSBitmapImageRep(data: tiff),
   let png = rep.representation(using: .png, properties: [:]) {
    try? png.write(to: dmgBgTarget)
}
print("   Done DMG background at \(dmgBgTarget.path).")

print("All asset generation completed successfully!")
