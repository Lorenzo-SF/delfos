use rustler::{Binary, Encoder, Env, Term};
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
        "elixir"     => Some(Language::new(tree_sitter_elixir::LANGUAGE)),
        "typescript" => Some(Language::new(tree_sitter_typescript::LANGUAGE_TYPESCRIPT)),
        "tsx"        => Some(Language::new(tree_sitter_typescript::LANGUAGE_TSX)),
        "javascript" => Some(Language::new(tree_sitter_javascript::LANGUAGE)),
        "python"     => Some(Language::new(tree_sitter_python::LANGUAGE)),
        "rust"       => Some(Language::new(tree_sitter_rust::LANGUAGE)),
        "go"         => Some(Language::new(tree_sitter_go::LANGUAGE)),
        "java"       => Some(Language::new(tree_sitter_java::LANGUAGE)),
        "csharp"     => Some(Language::new(tree_sitter_c_sharp::LANGUAGE)),
        "c"          => Some(Language::new(tree_sitter_c::LANGUAGE)),
        "cpp"        => Some(Language::new(tree_sitter_cpp::LANGUAGE)),
        "php"        => Some(Language::new(tree_sitter_php::LANGUAGE_PHP)),
        "ruby"       => Some(Language::new(tree_sitter_ruby::LANGUAGE)),
        "swift"      => Some(Language::new(tree_sitter_swift::LANGUAGE)),
        "dart"       => Some(Language::new(tree_sitter_dart::LANGUAGE)),
        "scala"      => Some(Language::new(tree_sitter_scala::LANGUAGE)),
        "lua"        => Some(Language::new(tree_sitter_lua::LANGUAGE)),
        "bash"       => Some(Language::new(tree_sitter_bash::LANGUAGE)),
        "r"          => Some(Language::new(tree_sitter_r::LANGUAGE)),
        "haskell"    => Some(Language::new(tree_sitter_haskell::LANGUAGE)),
        "erlang"     => Some(Language::new(tree_sitter_erlang::LANGUAGE)),
        "ocaml"      => Some(Language::new(tree_sitter_ocaml::LANGUAGE_OCAML)),
        "clojure"    => Some(Language::new(tree_sitter_clojure::LANGUAGE)),
        "zig"        => Some(Language::new(tree_sitter_zig::LANGUAGE)),
        "gleam"      => Some(Language::new(tree_sitter_gleam::LANGUAGE)),
        "julia"      => Some(Language::new(tree_sitter_julia::LANGUAGE)),
        "kotlin"     => Some(Language::new(tree_sitter_kotlin_ng::LANGUAGE)),
        "objc"       => Some(Language::new(tree_sitter_objc::LANGUAGE)),
        "asm"        => Some(Language::new(tree_sitter_asm::LANGUAGE)),
        "fsharp"     => Some(Language::new(tree_sitter_fsharp::LANGUAGE_FSHARP)),
        "powershell" => Some(Language::new(tree_sitter_powershell::LANGUAGE)),
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

        // ── R ───────────────────────────────────────────────────────────────
        ("r", "function_definition") => {
            let name = node_name(node, source);
            if !name.is_empty() {
                Some(Symbol {
                    qualified_name: if parent_name.is_empty() { name.clone() }
                                   else { format!("{}${}", parent_name, name) },
                    name,
                    kind: "function".to_string(),
                    line_start: node.start_position().row as u32 + 1,
                    line_end: node.end_position().row as u32 + 1,
                    visibility: "public".to_string(),
                    signature: String::new(),
                })
            } else { None }
        }

        // ── Haskell ─────────────────────────────────────────────────────────
        ("haskell", "bind") => {
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
        ("haskell", "data_type") | ("haskell", "newtype") => {
            let name = node_name(node, source);
            if !name.is_empty() {
                Some(Symbol {
                    qualified_name: name.clone(), name,
                    kind: "type".to_string(),
                    line_start: node.start_position().row as u32 + 1,
                    line_end: node.end_position().row as u32 + 1,
                    visibility: "public".to_string(),
                    signature: String::new(),
                })
            } else { None }
        }
        ("haskell", "class") => {
            let name = node_name(node, source);
            if !name.is_empty() {
                Some(Symbol {
                    qualified_name: name.clone(), name,
                    kind: "trait".to_string(),
                    line_start: node.start_position().row as u32 + 1,
                    line_end: node.end_position().row as u32 + 1,
                    visibility: "public".to_string(),
                    signature: String::new(),
                })
            } else { None }
        }

        // ── Erlang ──────────────────────────────────────────────────────────
        ("erlang", "function") => {
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
        ("erlang", "attribute") => {
            let text = extract_node_text(node, source);
            let kind_prefix = if text.starts_with("-module") { Some("module") }
                              else if text.starts_with("-record") { Some("struct") }
                              else if text.starts_with("-type") || text.starts_with("-opaque") { Some("type") }
                              else { None };
            if let Some(sym_kind) = kind_prefix {
                let name = node.child_by_field_name("name")
                    .map(|n| extract_node_text(&n, source).to_string())
                    .or_else(|| {
                        if let Some(start) = text.find('(') {
                            if let Some(end) = text.find(')') {
                                if end > start + 1 {
                                    let inner = text[start + 1..end].trim();
                                    // take first token (handle whitespace and quoted atoms)
                                    let first = inner.split([',', ' ', '\n']).next().unwrap_or("").trim_matches('\'');
                                    if !first.is_empty() {
                                        return Some(first.to_string());
                                    }
                                }
                            }
                        }
                        None
                    })
                    .unwrap_or_default();
                if !name.is_empty() {
                    Some(Symbol {
                        qualified_name: name.clone(), name,
                        kind: sym_kind.to_string(),
                        line_start: node.start_position().row as u32 + 1,
                        line_end: node.end_position().row as u32 + 1,
                        visibility: "public".to_string(),
                        signature: String::new(),
                    })
                } else { None }
            } else { None }
        }

        // ── OCaml ───────────────────────────────────────────────────────────
        ("ocaml", "value_definition") => {
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
        ("ocaml", "type_definition") => {
            let name = node_name(node, source);
            if !name.is_empty() {
                Some(Symbol {
                    qualified_name: name.clone(), name,
                    kind: "type".to_string(),
                    line_start: node.start_position().row as u32 + 1,
                    line_end: node.end_position().row as u32 + 1,
                    visibility: "public".to_string(),
                    signature: String::new(),
                })
            } else { None }
        }
        ("ocaml", "module_definition") => {
            let name = node_name(node, source);
            if !name.is_empty() {
                Some(Symbol {
                    qualified_name: name.clone(), name,
                    kind: "module".to_string(),
                    line_start: node.start_position().row as u32 + 1,
                    line_end: node.end_position().row as u32 + 1,
                    visibility: "public".to_string(),
                    signature: String::new(),
                })
            } else { None }
        }
        ("ocaml", "class_definition") => {
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

        // ── Zig ─────────────────────────────────────────────────────────────
        ("zig", "function_declaration") | ("zig", "function_signature") => {
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
        ("zig", "struct_declaration") => {
            let name = node_name(node, source);
            if !name.is_empty() {
                Some(Symbol {
                    qualified_name: name.clone(), name,
                    kind: "struct".to_string(),
                    line_start: node.start_position().row as u32 + 1,
                    line_end: node.end_position().row as u32 + 1,
                    visibility: "public".to_string(),
                    signature: String::new(),
                })
            } else { None }
        }
        ("zig", "enum_declaration") => {
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

        // ── Gleam ───────────────────────────────────────────────────────────
        ("gleam", "function") | ("gleam", "external_function") => {
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
        ("gleam", "type_definition") | ("gleam", "type_alias") => {
            let name = node_name(node, source);
            if !name.is_empty() {
                Some(Symbol {
                    qualified_name: name.clone(), name,
                    kind: "type".to_string(),
                    line_start: node.start_position().row as u32 + 1,
                    line_end: node.end_position().row as u32 + 1,
                    visibility: "public".to_string(),
                    signature: String::new(),
                })
            } else { None }
        }

        // ── Julia ───────────────────────────────────────────────────────────
        ("julia", "function_definition") => {
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
        ("julia", "module_definition") => {
            let name = node_name(node, source);
            if !name.is_empty() {
                Some(Symbol {
                    qualified_name: name.clone(), name,
                    kind: "module".to_string(),
                    line_start: node.start_position().row as u32 + 1,
                    line_end: node.end_position().row as u32 + 1,
                    visibility: "public".to_string(),
                    signature: String::new(),
                })
            } else { None }
        }
        ("julia", "struct_definition") => {
            let name = node_name(node, source);
            if !name.is_empty() {
                Some(Symbol {
                    qualified_name: name.clone(), name,
                    kind: "struct".to_string(),
                    line_start: node.start_position().row as u32 + 1,
                    line_end: node.end_position().row as u32 + 1,
                    visibility: "public".to_string(),
                    signature: String::new(),
                })
            } else { None }
        }

        // ── Objective-C ─────────────────────────────────────────────────────
        ("objc", "class_declaration")
        | ("objc", "class_interface")
        | ("objc", "class_implementation") => {
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
        ("objc", "method_declaration") | ("objc", "method_definition") => {
            let name = node_name(node, source);
            if !name.is_empty() {
                Some(Symbol {
                    qualified_name: if parent_name.is_empty() { name.clone() }
                                   else { format!("{}::{}", parent_name, name) },
                    name,
                    kind: "method".to_string(),
                    line_start: node.start_position().row as u32 + 1,
                    line_end: node.end_position().row as u32 + 1,
                    visibility: "public".to_string(),
                    signature: String::new(),
                })
            } else { None }
        }
        ("objc", "protocol_declaration") => {
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

        // ── Assembly ────────────────────────────────────────────────────────
        ("asm", "label") => {
            let name = node_name(node, source);
            if !name.is_empty() {
                Some(Symbol {
                    qualified_name: name.clone(), name,
                    kind: "variable".to_string(),
                    line_start: node.start_position().row as u32 + 1,
                    line_end: node.end_position().row as u32 + 1,
                    visibility: "public".to_string(),
                    signature: String::new(),
                })
            } else { None }
        }

        // ── F# ──────────────────────────────────────────────────────────────
        ("fsharp", "function_or_value_defn")
        | ("fsharp", "function_decl")
        | ("fsharp", "val_defn") => {
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
        ("fsharp", "type_defn") | ("fsharp", "class_defn") | ("fsharp", "module_defn") => {
            let name = node_name(node, source);
            if !name.is_empty() {
                let sym_kind = match kind {
                    "type_defn" => "type",
                    "class_defn" => "class",
                    _ => "module",
                };
                Some(Symbol {
                    qualified_name: name.clone(), name,
                    kind: sym_kind.to_string(),
                    line_start: node.start_position().row as u32 + 1,
                    line_end: node.end_position().row as u32 + 1,
                    visibility: "public".to_string(),
                    signature: String::new(),
                })
            } else { None }
        }

        // ── PowerShell ────────────────────────────────────────────────────
        ("powershell", "function") => {
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
            let map = Term::map_new(env);
            let map = map.map_put("name".encode(env), s.name.encode(env)).unwrap();
            let map = map.map_put("qualified_name".encode(env), s.qualified_name.encode(env)).unwrap();
            let map = map.map_put("kind".encode(env), s.kind.encode(env)).unwrap();
            let map = map.map_put("line_start".encode(env), s.line_start.encode(env)).unwrap();
            let map = map.map_put("line_end".encode(env), s.line_end.encode(env)).unwrap();
            let map = map.map_put("visibility".encode(env), s.visibility.encode(env)).unwrap();
            map.map_put("signature".encode(env), s.signature.encode(env)).unwrap()
        })
        .collect();

    (atoms::ok(), result).encode(env)
}

/// supported_languages() :: [binary]
#[rustler::nif]
fn supported_languages() -> Vec<&'static str> {
    vec![
        "elixir", "typescript", "tsx", "javascript",
        "python", "rust", "go", "java",
        "csharp", "c", "cpp", "php", "ruby", "swift",
        "dart", "scala", "lua", "bash",
        "r", "haskell", "erlang", "ocaml", "clojure",
        "zig", "gleam", "julia", "kotlin", "objc",
        "asm", "fsharp", "powershell",
    ]
}

rustler::init!("Elixir.Delfos.Parsers.TreeSitter.NIF");
