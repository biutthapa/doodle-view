//
//  Core.swift
//

import Foundation
import SwiftUI

// MARK: Reps
func READ(_ input: String) -> [Expr] {
    if input == "quit" || input == "exit" {
        exit(0)
    }
    return readStr(input)
}

func PRINT(_ expr: Expr) -> String {
    return prnStr(expr)
}

func EVAL(_ expr: Expr, _ env: Env) throws -> Expr {
    switch expr {
    case .list(let items) where !items.isEmpty:
        if case .symbol(_) = items.first() {
             if let applied = try apply(items: items, env: env) {
                 return applied
             }
        }
        return try evalList(items: items, env: env)
    case .list:
        return expr
    default:
        return try evalAST(expr, env)
    }
}

func rep(_ input: String, _ env: Env) throws -> (output: String, env: Env) {
    let exprs = READ(input)
    let stringOutput = try exprs.map { expr in
        let resExpr = try EVAL(expr, env)
        return PRINT(resExpr)
    }.joined(separator: "\n")
    return (output: stringOutput, env: env)
}

public func initialEnv() -> Env {
    return Env(outer: nil)
        .set(data: coreNS
            .reduce(into: [String: Expr]()) { result, pair in
                result[pair.key] = .lambda(pair.value)
            })
}

public func initialEnv(custom: [String: Lambda]) -> Env {
    let data = coreNS.merging(custom) { _, new in
        return new
    }
    
    return Env(outer: nil)
        .set(data: data
            .reduce(into: [String: Expr]()) { result, pair in
                result[pair.key] = .lambda(pair.value)
            })
}

func applyDef(arguments: [Expr], env: Env) throws -> Expr? {
    guard arguments.count == 2 else {
        throw EvalError.wrongNumberOfArgument(inOperation: "def!", expected: 2.description, found: arguments.count.description)
    }
    guard case let .symbol(name) = arguments.first() else {
        throw EvalError.invalidName(inOperation: "def!")
    }
    let value = try EVAL(arguments.rest().first()!, env)
    let _ = env.set(symbol: name, value: value)
    return value
}

func applyLet(arguments: [Expr], env: Env) throws -> Expr? {
    guard arguments.count == 2 else {
        throw EvalError.wrongNumberOfArgument(inOperation: "let*",
                                              expected: 2.description,
                                              found: arguments.count.description)
    }
    
    let bindings: [Expr]
    switch arguments.first() {
    case .vector(let vectorBindings):
        bindings = vectorBindings
    case .list(let listBindings):
        bindings = listBindings
    default:
        throw EvalError.generalError("The bindings for let must be a vector or a list.")
    }
    guard bindings.count % 2 == 0 else {
        throw EvalError.generalError("The bindings for let supposed be in piars.")
    }
    guard let expression = arguments.rest().first() else {
        throw EvalError.generalError("The expression for let is not valid.")
    }
    let innerEnv = Env(outer: env)
    let bindingDictionairy = try bindings.toDictionary()
    for binding in bindingDictionairy {
        let evaluatedVal = try EVAL(binding.value, innerEnv)
        let _ = innerEnv.set(symbol: binding.key, value: evaluatedVal)
    }
    return try EVAL(expression, innerEnv)
}

func applyDo(expressions: [Expr], env: Env) throws -> Expr? {
    return try expressions.map { try EVAL($0, env) }.last
}

func applyIf(arguments: [Expr], env: Env) throws -> Expr? {
    guard 2...3 ~= arguments.count else {
        throw EvalError.wrongNumberOfArgument(inOperation: "if", expected: "2 or 3", found: String(arguments.count))
    }
    guard let predicate = arguments.first() else {
        throw EvalError.invalidPredicate(inOperation: "if")
    }
    guard let ifTrueExpr = arguments.rest().first() else {
        throw EvalError.generalError("if true expression is invalid")
    }
    let ifFalseExpr = arguments.rest().rest().first()
    let evaluatedPredicate = try EVAL(predicate, env)
    switch evaluatedPredicate {
    case .boolean(false), .nil:
        return try EVAL(ifFalseExpr ?? .nil, env)
    default:
        return try EVAL(ifTrueExpr, env)
    }
}


func applyFn(items: [Expr], env: Env) throws -> Expr? {
    guard case let .symbol(symbol) = items.first() else { throw EvalError.generalError("Symbol invalid") }
    let arguments = items.rest() // this mayn not be right
    guard arguments.count == 2 else {
        throw EvalError.wrongNumberOfArgument(inOperation: symbol, expected: "2", found: String(arguments.count))
    }

    let lambdaArgKeysExpr: [Expr]
    switch arguments.first() {
    case .vector(let vectorArgs):
        lambdaArgKeysExpr = vectorArgs
    case .list(let listArgs):
        lambdaArgKeysExpr = listArgs
    default:
        throw EvalError.generalError("The lambda args must be in a vector or a list.")
    }
    
    let lambdaArgKeys: [String] = try lambdaArgKeysExpr.map { expr in
        guard case .symbol(let key) = expr else {
            throw EvalError.generalError("invalid arg binding key in lambda.")
        }
        return key
    }
    
    let lambdaBody: [Expr] = arguments.rest()
    
    return .lambda { lambdaArgValues in
        // in ((fn* [x] (+ x 1)) 3) or (inc 3) with (def! inc (fn* [x] (+ x 1)))
        // in closureEnv, gotta set x = 3.
        // argKeys = ["x"] and argVals = [.number(3)]
        
        // in ((fn* [a b] (+ a b)) 6 4) or (add 3) with (def! add (fn* [a b] (+ a b)))
        // in closureEnv, gotta set a = 6 and b = 4.
        // argKeys = ["a", "b"] and argVals = [.number(6), .number(4)]
        
        let lambdaBinds: [String: Expr] = Dictionary.buildFrom(keys: lambdaArgKeys,
                                                               values: lambdaArgValues)
        let closureEnv = Env(outer: env, binds: lambdaBinds)
        guard let evaluatedLambdaValue = try lambdaBody.map({ try EVAL($0, closureEnv) }).last() else {
            throw EvalError.generalError("Something wrong whaile evaluating lambda body")
        }
        return evaluatedLambdaValue
    }
    
}


func apply(items: [Expr], env: Env) throws -> Expr? {
    guard case .symbol(let symbol) = items.first() else {
        throw EvalError.generalError("First item in apply invalid")
    }
    let arguments = items.rest()
    switch symbol {
    case "def!":
        return try applyDef(arguments: arguments, env: env)
    case "let*":
        return try applyLet(arguments: arguments, env: env)
    case "do":
        return try applyDo(expressions: arguments, env: env)
    case "if":
        return try applyIf(arguments: arguments, env: env)
    case "fn*", "lambda":
        return try applyFn(items: items, env: env)
    default:
        return nil
    }       
}


func evalList(items: [Expr], env: Env) throws -> Expr {
    let evaluatedList = try items.map { try EVAL($0, env) }
    // TODO: What about for quoted list??
    guard case .lambda(let function) = evaluatedList.first else {
        throw ParserError.invalidInput("First item in list is expected to be a lambda.")
    }
    // Further evaluate any nested lists within the arguments
    let arguments = try evaluatedList.rest().map { item in
        if case .list(_) = item {
            return try EVAL(item, env)
        } else {
            return item
        }
    }
    return try function(arguments)
}

func evalAST(_ ast: Expr, _ env: Env) throws -> Expr {
    switch ast {
    case .list(let items):
        let newList = try items.map { try EVAL($0, env) }
        return .list(newList)

    case .symbol(let sym):
        let val = try env.get(symbol: sym)
        return val

    case .vector(let items):
        return .vector(try items.map { try EVAL($0, env) })

    case .map(let items):
        var newMap = [ExprKey: Expr]()
        for (key, value) in items {
            let evaluatedValue = try EVAL(value, env)
            newMap[key] = evaluatedValue
        }
        return .map(newMap)

    default:
        return ast
    }
}

// MARK: Namespaces/Lambdas
public let viewsNS: [String: Lambda] = [
    "text": { args in
        guard args.count >= 1, case let .string(text) = args[0] else {
            throw ViewError.missingRequiredArgument("Text content is required.")
        }

        let modifiers = TextModifiers(font: nil,
                                      fontWeight: nil,
                                      foregroundColor: nil,
                                      fontSize: nil,
                                      backgroundColor: nil,
                                      customFontName: nil)
        
        return .view(.text(text, modifiers))
    },
    "rect": { args in
        guard args.count >= 1, let properties = args.first, case .map(let propertiesMap) = properties else {
            throw ViewError.missingRequiredArgument("Property map is required for rectangle.")
        }
        
        // Extract color
        let color = propertiesMap[.keyword("color")].flatMap { colorFromString($0) } ?? .black

        // Extract size
        let size: CGSize = propertiesMap[.keyword("size")].flatMap { sizeExpr in
            guard case .map(let sizeMap) = sizeExpr,
                  let widthExpr = sizeMap[.keyword("width")], case .number(let width) = widthExpr,
                  let heightExpr = sizeMap[.keyword("height")], case .number(let height) = heightExpr else {
                return CGSize(width: 100, height: 100) // Default size if not specified
            }
            return CGSize(width: width, height: height)
        } ?? CGSize(width: 100, height: 100) // Default size if size key is missing

        return .view(.rect(color, size))
    }

]


// MARK: Make Views
public func readViewExprs(from input: String, env: Env) -> [Expr.ViewExpr] {
    let trimmedString = input.trimmingCharacters(in: .whitespacesAndNewlines)
    let exprs = READ(trimmedString)
    var viewExprs: [Expr.ViewExpr] = []

    for expr in exprs {
        // Check if this is a definition; skip transforming into a view expression
        if case .list(let items) = expr, items.first == .symbol("def!") {
            // Evaluate the definition to update the environment but do not add to view expressions
            _ = try? EVAL(expr, env)
            continue
        }
        
        // For non-definition expressions, evaluate and attempt to transform into view expressions
        do {
            let evaluatedExpr = try EVAL(expr, env)
            if let viewExpr = transformToViewExpr(evaluatedExpr) {
                viewExprs.append(viewExpr)
            }
        } catch {
            print("Error evaluating expression for view: \(error)")
        }
    }
    return viewExprs
}


private func transformToViewExpr(_ expr: Expr) -> Expr.ViewExpr? {
    switch expr {
    case .map(let properties):
        guard let typeExpr = properties[.keyword("ui/type")], case let .keyword(type) = typeExpr else {
            return nil
        }
        switch type {
        case "text":
            if let text = properties[.keyword("text")], case let .string(content) = text {
                let modifiers = extractTextModifiers(from: properties)
                return .text(content, modifiers)
            }
        case "rectangle":
            let modifiers = extractRectModifiers(from: properties)
            if let color = modifiers.color {
                let size = modifiers.size ?? CGSize(width: 100, height: 100)
                return .rect(color, size)
            }
        default:
            print("Unsupported view type: \(type)")
        }
    default:
        return nil
    }
    return nil
}


private func extractTextModifiers(from properties: [ExprKey: Expr]) -> TextModifiers {
    let fontWeight = properties[.keyword("fontWeight")].flatMap { fontWeightString(from: $0) }
    let fontSize = properties[.keyword("fontSize")].flatMap { if case let .number(value) = $0 { return CGFloat(value) } else { return nil } }
    let color = properties[.keyword("foreground-color")].flatMap { colorFromString($0) }
    let customFontName = properties[.keyword("customFontName")].flatMap { if case let .string(value) = $0 { return value } else { return nil } }

    return TextModifiers(font: nil,
                         fontWeight: fontWeight,
                         foregroundColor: color,
                         fontSize: fontSize,
                         backgroundColor: nil,
                         customFontName: customFontName)

}

private func extractRectModifiers(from properties: [ExprKey: Expr]) -> RectModifiers {
    let color = properties[.keyword("color")].flatMap { colorFromString($0) }
    let size: CGSize? = properties[.keyword("size")].flatMap { sizeExpr in
        guard case .map(let sizeMap) = sizeExpr,
              let widthExpr = sizeMap[.keyword("width")], case .number(let width) = widthExpr,
              let heightExpr = sizeMap[.keyword("height")], case .number(let height) = heightExpr else {
            return nil
        }
        return CGSize(width: width, height: height)
    }

    return RectModifiers(frame: nil,
                         color: color,
                         size: size,
                         cornerRadios: nil)

}




private func fontWeightString(from expr: Expr) -> Font.Weight? {
    guard case let .string(value) = expr else { return nil }
    switch value.lowercased() {
    case "ultralight": return .ultraLight
    case "thin": return .thin
    case "light": return .light
    case "regular": return .regular
    case "medium": return .medium
    case "semibold": return .semibold
    case "bold": return .bold
    case "heavy": return .heavy
    case "black": return .black
    default: return nil
    }
}

private func colorFromString(_ expr: Expr) -> Color? {
    switch expr {
    case .keyword(let colorName):
        switch colorName {
        case "red": return .red
        case "blue": return .blue
        case "green": return .green
        case "black": return .black
        case "yellow": return .yellow
        case "white": return .white
        default: return nil
        }
    default:
        return nil
    }
}


@ViewBuilder
public func makeView(from viewExpr: Expr.ViewExpr) -> some View {
    switch viewExpr {
    case let .text(string, modifiers):
        Text(string)
            .fontWeight(modifiers.fontWeight)
            .font(.custom(modifiers.customFontName ?? "System", size: modifiers.fontSize ?? 17))
            .foregroundColor(modifiers.foregroundColor ?? .primary)
    case let .rect(color, size):
        Rectangle()
            .fill(color)
            .frame(width: size.width, height: size.height)
    default:
        Text("Potato")
    }
}
