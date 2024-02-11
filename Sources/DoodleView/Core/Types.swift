//
//  Types.swift
//
//
//  Created by Biut Raj Thapa on 29/12/2023.
//

import Foundation
import SwiftUI

public typealias Lambda = ([Expr]) throws -> Expr
public typealias ViewLambda = ([Expr]) throws -> any View
public typealias Number = Double

public enum ExprKey: Hashable {
    case symbol(String)
    case keyword(String)
    case number(Number)
    case boolean(Bool)
    case string(String)
    case list([Expr])
    case vector([Expr])
//    indirect case pair(ExprKey, Expr)
    case map([ExprKey: Expr])
    case `nil`
}

public enum Expr {
    case symbol(String)
    case keyword(String)
    case number(Number)
    case `nil`
    case boolean(Bool)
    case string(String)
//    indirect case pair(ExprKey, Expr)
    indirect case list([Expr])
    indirect case vector([Expr])
    indirect case map([ExprKey: Expr])
    indirect case lambda(Lambda)
    
    case view(ViewExpr)
    
    public indirect enum ViewExpr {
        case hStack(ViewExpr)
        case vStack(ViewExpr)
        case zStack(ViewExpr)
        
        case text(String, TextModifiers)
        case rect(Color, CGSize)
        
    }
    
}

public struct TextModifiers {
    let font: Font?
    let fontWeight: Font.Weight?
    let foregroundColor: Color?
    let fontSize: CGFloat?
    let backgroundColor: Color?
    let customFontName: String?
}

public struct RectModifiers {
    let frame: (width: CGFloat?,
                height: CGFloat?,
                alignment: Alignment)?
    let color: Color?
    let size: CGSize?
    let cornerRadios: CGFloat?
}


enum ViewError: Error {
    case typeMismatch(expected: String, found: String)
    case missingRequiredArgument(String)
    case unsupportedViewType(String)
    case invalidModifierValue(String)
    case custom(String)
}



public enum DataError: Error {
    case unequalKeyValueCount(String)
}

public enum ParserError: Error {
    case invalidInput(String)
    case generalError(String)
    case unexpectedEndOfInput
    case unbalancedParentheses
    case invalidMapKey
}

public enum EnvError: Error {
    case symbolNotFound(String)
    case symbolNotFound(symbol: String, available: [String])
}

public enum EvalError: Error {
    case wrongNumberOfArgument(inOperation: String, expected: String, found: String)
    case invalidArgument(argument: String, inOperation: String)
    case invalidPredicate(inOperation: String)
    case invalidSymbol(inOperation: String)
    case invalidName(inOperation: String)
    case generalError(String)
}

public enum MathError: Error {
    case divisionByZero(inOperation: String)
}
