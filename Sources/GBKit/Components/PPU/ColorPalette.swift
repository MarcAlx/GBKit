import Foundation

/// An rgb color
public struct Color {
    
    /// red component
    public let r:Byte
    
    /// green component
    public let g:Byte
    
    /// blue component
    public let b:Byte
    
    public init(_ r:Byte, _ g:Byte, _ b:Byte){
        self.r = r
        self.g = g
        self.b = b
    }
}

/// a color palette, made of three colors
public struct ColorPalette {
    private var values:[Color]
    
    public subscript(colorIndex:Int) -> Color {
        get {
            return self.values[colorIndex]
        }
        set {
            self.values[colorIndex] = newValue
        }
    }
    
    /// init with values from light to dark
    public init(_ values:[Color]) {
        assert(values.count == 4, "color must have exactly 4 colors")
        self.values = values
    }
    
    /// init a color palette from a reference palette and a byte that define shuffling (@see FF47 mmu address)
    public init(paletteData:Byte, reference:ColorPalette){
        //todo keep only lower two bit via & 0b0000_0011 instead of double shifting
        let color3Index = (paletteData /*<< 0*/) >> 6
        let color2Index = (paletteData << 2) >> 6
        let color1Index = (paletteData << 4) >> 6
        let color0Index = (paletteData << 6) >> 6
        self.init([
            reference[Int(color0Index)],
            reference[Int(color1Index)],
            reference[Int(color2Index)],
            reference[Int(color3Index)]
        ])
    }
}
