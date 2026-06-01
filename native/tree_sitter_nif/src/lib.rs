use rustler::{Atom, Binary, Encoder, Env, NifResult, Term};
use tree_sitter::{Language, Node, Parser};

mod atoms {
    rustler::atoms! {
        ok,
        error,
        function,
        method,
        class,
        module,
        r#struct,
        r#enum,
        interface,
        trait_def,
        impl_block,
        macro_def,
        variable,
        constant,
        type_alias,
        unknown
    }
}

// ── Language registry ────────────────────────────────────────────────────────

fn language_for(lang: &str) -> Option<Language> {
    match lang {
        "elixir"     => Some(tree_sitter_elixir::language()),
        "typescript" => Some(tree_sitter_typescript::language_typescript()),
        "tsx"        => Some(tree_sitter_typescript::language_tsx()),
        "javascript" => Some(tree_sitter_javascript::language()),
        "python"     => Some(tree_sitter_python::language()),
        "rust"       => Some(tree_sitter_rust::language()),
        "go"         => Some(tree_sitter_go::language()),
        "java"       => Some(tree_sitter_java::language()),
        "kotlin"     => Some(tree_sitter_kotlin::language()),
        "csharp"     => Some(tree_sitter_c_sharp::language()),
        "c"          => Some(tree_sitter_c::language()),
        "cpp"        => Some(tree_sitter_cpp::language()),
        "php"        => Some(tree_sitter_php::language_php()),
        "ruby"       => Some(tree_sitter_ruby::language()),
        "swift"      => Some(tree_sitter_swift::language()),
        "dart"       => Some(tree_sitter_dart::language()),
        "scala"      => Some(tree_sitter_scala::language()),
        "lua"        => Some(tree_sitter_lua::language()),
        "bash"       => Some(tree_sitter_bash::language()),
        _            => None,
    }
}

// ── Symbol extraction ─────────────────────────────────────────────────────────

#[derive(Debug)]
struct Symbol {
    name: String,
    qualified_name: String,
    kind: String,
    line_start: u32,
    line_end: u32,
    visibility: String,
    signature: String,
}

fn extract_node_text<'a>(node: &Node, source: &'a [u8]) -> &'a str {
    node.utf8_text(source).unwrap_or("")
}

fn node_name(node: &Node, source: &[u8]) -> String {
    // Try common "name" field first, fallback to first named child text
    if let Some(name_node) = node.child_by_field_name("name") {
        return extract_node_text(&name_node, source).to_string();
    }
    String::new()
}

fn extract_symbols(node: &Node, source: &[u8], lang: &str, parent_name: &str) -> Vec<Symbol> {
    let mut symbols = Vec::new();
    let kind = node.kind();

    let sym = match (lang, kind) {
        // ── Elixir ─────────────────────────────────────────────────────────
        ("elixir", "call") => {
            let func = node.child_by_field_name("target")
                .map(|n| extract_node_text(&n, source))
                .unwrap_or("");
            match func {
                "def" | "defp" | "defmacro" | "defmacrop" => {
                    let args = node.child_by_field_name("arguments");
                    let name = args.and_then(|a| a.named_child(0))
                        .map(|n| extract_node_text(&n, source).split('(').next().unwrap_or("").to_string())
                        .unwrap_or_default();
                    if !name.is_empty() {
                        let visibility = if func == "defp" || func == "defmacrop" { "private" } else { "public" };
                        let sym_kind = if func.starts_with("defmacro") { "macro" } else { "function" };
                        Some(Symbol {
                            qualified_name: if parent_name.is_empty() { name.clone() }
                                           else { format!("{}.{}", parent_name, name) },
                            name,
                            kind: sym_kind.to_string(),
                            line_start: node.start_position().row as u32 + 1,
                            line_end: node.end_position().row as u32 + 1,
                            visibility: visibility.to_string(),
                            signature: String::new(),
                        })
                    } else { None }
                }
                "defmodule" | "defprotocol" | "defimpl" => {
                    let args = node.child_by_field_name("arguments");
                    let name = args.and_then(|a| a.named_child(0))
                        .map(|n| extract_node_text(&n, source).to_string())
                        .unwrap_or_default();
                    if !name.is_empty() {
                        Some(Symbol {
                            qualified_name: name.clone(),
                            name,
                            kind: if func == "defmodule" { "module" } else { "protocol" }.to_string(),
                            line_start: node.start_position().row as u32 + 1,
                            line_end: node.end_position().row as u32 + 1,
                            visibility: "public".to_string(),
                            signature: String::new(),
                        })
                    } else { None }
                }
                _ => None,
            }
        }

        // ── TypeScript / JavaScript ────────────────────────────────────────
        (l, "function_declaration") | (l, "function_expression")
            if l == "typescript" || l == "javascript" || l == "tsx" =>
        {
            let name = node_name(node, source);
            if !name.is_empty() {
                Some(Symbol {
                    qualified_name: if parent_name.is_empty() { name.clone() }
                                   else { format!("{}.{}", parent_name, name) },
                    name,
                    kind: "function".to_string(),
                    line_start: node.start_position().row as u32 + 1,
                    line_end: node.end_position().row as u32 + 1,
                    visibility: "public".to_string(),
                    signature: String::new(),
                })
            } else { None }
        }
        (l, "method_definition") if l == "typescript" || l == "javascript" || l == "tsx" => {
            let name = node_name(node, source);
            if !name.is_empty() {
                let vis = if node.child_by_field_name("accessibility")
                    .map(|n| extract_node_text(&n, source))
                    .unwrap_or("") == "private" { "private" } else { "public" };
                Some(Symbol {
                    qualified_name: if parent_name.is_empty() { name.clone() }
                                   else { format!("{}.{}", parent_name, name) },
                    name,
                    kind: "method".to_string(),
                    line_start: node.start_position().row as u32 + 1,
                    line_end: node.end_position().row as u32 + 1,
                    visibility: vis.to_string(),
                    signature: String::new(),
                })
            } else { None }
        }
        (l, "class_declaration") | (l, "abstract_class_declaration")
            if l == "typescript" || l == "javascript" || l == "tsx" =>
        {
            let name = node_name(node, source);
            if !name.is_empty() {
                Some(Symbol {
                    qualified_name: name.clone(),
                    name,
                    kind: "class".to_string(),
                    line_start: node.start_position().row as u32 + 1,
                    line_end: node.end_position().row as u32 + 1,
                    visibility: "public".to_string(),
                    signature: String::new(),
                })
            } else { None }
        }
        (l, "interface_declaration") if l == "typescript" || l == "tsx" => {
            let name = node_name(node, source);
            if !name.is_empty() {
                Some(Symbol {
                    qualified_name: name.clone(), name,
                    kind: "interface".to_string(),
                    line_start: node.start_position().row as u32 + 1,
                    line_end: node.end_position().row as u32 + 1,
                    visibility: "public".to_string(),
                    signature: String::new(),
                })
            } else { None }
        }
        (l, "enum_declaration") if l == "typescript" || l == "tsx" => {
            let name = node_name(node, source);
            if !name.is_empty() {
                Some(Symbol {
                    qualified_name: name.clone(), name,
                    kind: "enum".to_string(),
                    line_start: node.start_position().row as u32 + 1,
                    line_end: node.end_position().row as u32 + 1,
                    visibility: "public".to_string(),
                    signature: String::new(),
                })
            } else { None }
        }

        // ── Python ─────────────────────────────────────────────────────────
        ("python", "function_definition") => {
            let name = node_name(node, source);
            if !name.is_empty() {
                let vis = if name.starts_with("__") && name.ends_with("__") { "dunder" }
                          else if name.starts_with('_') { "private" }
                          else { "public" };
                Some(Symbol {
                    qualified_name: if parent_name.is_empty() { name.clone() }
                                   else { format!("{}.{}", parent_name, name) },
                    name,
                    kind: if parent_name.is_empty() { "function" } else { "method" }.to_string(),
                    line_start: node.start_position().row as u32 + 1,
                    line_end: node.end_position().row as u32 + 1,
                    visibility: vis.to_string(),
                    signature: String::new(),
                })
            } else { None }
        }
        ("python", "class_definition") => {
            let name = node_name(node, source);
            if !name.is_empty() {
                Some(Symbol {
                    qualified_name: name.clone(), name,
                    kind: "class".to_string(),
                    line_start: node.start_position().row as u32 + 1,
                    line_end: node.end_position().row as u32 + 1,
                    visibility: "public".to_string(),
                    signature: String::new(),
                })
            } else { None }
        }

        // ── Rust ───────────────────────────────────────────────────────────
        ("rust", "function_item") => {
            let name = node_name(node, source);
            if !name.is_empty() {
                let vis = node.child_by_field_name("visibility")
                    .map(|n| extract_node_text(&n, source))
                    .map(|v| if v.starts_with("pub") { "public" } else { "private" })
                    .unwrap_or("private");
                Some(Symbol {
                    qualified_name: if parent_name.is_empty() { name.clone() }
                                   else { format!("{}::{}", parent_name, name) },
                    name,
                    kind: "function".to_string(),
                    line_start: node.start_position().row as u32 + 1,
                    line_end: node.end_position().row as u32 + 1,
                    visibility: vis.to_string(),
                    signature: String::new(),
                })
            } else { None }
        }
        ("rust", "struct_item") | ("rust", "enum_item") | ("rust", "trait_item") => {
            let name = node_name(node, source);
            if !name.is_empty() {
                let sym_kind = match kind {
                    "struct_item" => "struct",
                    "enum_item"   => "enum",
                    _             => "trait",
                };
                let vis = node.child_by_field_name("visibility")
                    .map(|n| extract_node_text(&n, source))
                    .map(|v| if v.starts_with("pub") { "public" } else { "private" })
                    .unwrap_or("private");
                Some(Symbol {
                    qualified_name: name.clone(), name,
                    kind: sym_kind.to_string(),
                    line_start: node.start_position().row as u32 + 1,
                    line_end: node.end_position().row as u32 + 1,
                    visibility: vis.to_string(),
                    signature: String::new(),
                })
            } else { None }
        }
        ("rust", "impl_item") => {
            let type_name = node.child_by_field_name("type")
                .map(|n| extract_node_text(&n, source).to_string())
                .unwrap_or_default();
            if !type_name.is_empty() {
                Some(Symbol {
                    qualified_name: format!("impl {}", type_name),
                    name: type_name.clone(),
                    kind: "impl".to_string(),
                    line_start: node.start_position().row as u32 + 1,
                    line_end: node.end_position().row as u32 + 1,
                    visibility: "public".to_string(),
                    signature: String::new(),
                })
            } else { None }
        }

        // ── Go ─────────────────────────────────────────────────────────────
        ("go", "function_declaration") | ("go", "method_declaration") => {
            let name = node_name(node, source);
            if !name.is_empty() {
                let vis = if name.chars().next().map(|c| c.is_uppercase()).unwrap_or(false)
                    { "public" } else { "private" };
                Some(Symbol {
                    qualified_name: if parent_name.is_empty() { name.clone() }
                                   else { format!("{}.{}", parent_name, name) },
                    name,
                    kind: if kind == "method_declaration" { "method" } else { "function" }.to_string(),
                    line_start: node.start_position().row as u32 + 1,
                    line_end: node.end_position().row as u32 + 1,
                    visibility: vis.to_string(),
                    signature: String::new(),
                })
            } else { None }
        }
        ("go", "type_declaration") => {
            let name = node_name(node, source);
            if !name.is_empty() {
                let vis = if name.chars().next().map(|c| c.is_uppercase()).unwrap_or(false)
                    { "public" } else { "private" };
                Some(Symbol {
                    qualified_name: name.clone(), name,
                    kind: "type".to_string(),
                    line_start: node.start_position().row as u32 + 1,
                    line_end: node.end_position().row as u32 + 1,
                    visibility: vis.to_string(),
                    signature: String::new(),
                })
            } else { None }
        }

        // ── Java / Kotlin / C# ────────────────────────────────────────────
        (l, "class_declaration") if matches!(l, "java" | "kotlin" | "csharp") => {
            let name = node_name(node, source);
            if !name.is_empty() {
                Some(Symbol {
                    qualified_name: name.clone(), name,
                    kind: "class".to_string(),
                    line_start: node.start_position().row as u32 + 1,
                    line_end: node.end_position().row as u32 + 1,
                    visibility: "public".to_string(),
                    signature: String::new(),
                })
            } else { None }
        }
        (l, "method_declaration") if matches!(l, "java" | "kotlin" | "csharp") => {
            let name = node_name(node, source);
            if !name.is_empty() {
                Some(Symbol {
                    qualified_name: if parent_name.is_empty() { name.clone() }
                                   else { format!("{}.{}", parent_name, name) },
                    name,
                    kind: "method".to_string(),
                    line_start: node.start_position().row as u32 + 1,
                    line_end: node.end_position().row as u32 + 1,
                    visibility: "public".to_string(),
                    signature: String::new(),
                })
            } else { None }
        }

        _ => None,
    };

    if let Some(s) = sym {
        let new_parent = s.qualified_name.clone();
        symbols.push(s);
        // Recurse into children with updated parent context
        let mut cursor = node.walk();
        for child in node.children(&mut cursor) {
            let mut child_syms = extract_symbols(&child, source, lang, &new_parent);
            symbols.append(&mut child_syms);
        }
    } else {
        // No match at this level — recurse with same parent
        let mut cursor = node.walk();
        for child in node.children(&mut cursor) {
            let mut child_syms = extract_symbols(&child, source, lang, parent_name);
            symbols.append(&mut child_syms);
        }
    }

    symbols
}

// ── NIF entry points ─────────────────────────────────────────────────────────

/// parse_symbols(language :: binary, source :: binary) :: {:ok, [symbol_map]} | {:error, reason}
#[rustler::nif(schedule = "DirtyCpu")]
fn parse_symbols<'a>(env: Env<'a>, language: &str, source: Binary) -> Term<'a> {
    let lang = match language_for(language) {
        Some(l) => l,
        None => {
            let err = format!("unsupported language: {}", language);
            return (atoms::error(), err).encode(env);
        }
    };

    let mut parser = Parser::new();
    parser.set_language(&lang).expect("language load failed");

    let src_bytes = source.as_slice();
    let tree = match parser.parse(src_bytes, None) {
        Some(t) => t,
        None => return (atoms::error(), "parse returned None").encode(env),
    };

    let symbols = extract_symbols(&tree.root_node(), src_bytes, language, "");

    let result: Vec<rustler::Term<'a>> = symbols
        .iter()
        .map(|s| {
            let map = rustler::types::map::map_new(env);
            let map = rustler::types::map::map_put(env, map,
                "name".encode(env), s.name.encode(env)).unwrap();
            let map = rustler::types::map::map_put(env, map,
                "qualified_name".encode(env), s.qualified_name.encode(env)).unwrap();
            let map = rustler::types::map::map_put(env, map,
                "kind".encode(env), s.kind.encode(env)).unwrap();
            let map = rustler::types::map::map_put(env, map,
                "line_start".encode(env), s.line_start.encode(env)).unwrap();
            let map = rustler::types::map::map_put(env, map,
                "line_end".encode(env), s.line_end.encode(env)).unwrap();
            let map = rustler::types::map::map_put(env, map,
                "visibility".encode(env), s.visibility.encode(env)).unwrap();
            rustler::types::map::map_put(env, map,
                "signature".encode(env), s.signature.encode(env)).unwrap()
        })
        .collect();

    (atoms::ok(), result).encode(env)
}

/// supported_languages() :: [binary]
#[rustler::nif]
fn supported_languages() -> Vec<&'static str> {
    vec![
        "elixir", "typescript", "tsx", "javascript",
        "python", "rust", "go", "java", "kotlin",
        "csharp", "c", "cpp", "php", "ruby", "swift",
        "dart", "scala", "lua", "bash",
    ]
}

rustler::init!("Elixir.Delfos.Parsers.TreeSitter.NIF", [parse_symbols, supported_languages]);
