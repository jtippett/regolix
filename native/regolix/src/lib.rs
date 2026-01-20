use regorus::Engine;
use rustler::{Atom, Encoder, Env, ResourceArc, Term};
use std::collections::HashMap;
use std::sync::RwLock;

mod atoms {
    rustler::atoms! {
        ok,
        error,
        undefined,
        parse_error,
        eval_error,
        json_error,
        engine_error,
    }
}

pub struct EngineResource {
    engine: RwLock<Engine>,
    policies: RwLock<HashMap<String, String>>,
}

#[rustler::resource_impl]
impl rustler::Resource for EngineResource {}

#[rustler::nif]
fn native_new() -> ResourceArc<EngineResource> {
    ResourceArc::new(EngineResource {
        engine: RwLock::new(Engine::new()),
        policies: RwLock::new(HashMap::new()),
    })
}

#[rustler::nif]
fn native_add_policy(
    resource: ResourceArc<EngineResource>,
    name: String,
    source: String,
) -> Result<(), (Atom, String)> {
    let mut engine = resource
        .engine
        .write()
        .map_err(|e| (atoms::engine_error(), e.to_string()))?;

    // Store the source for later rule extraction
    let mut policies = resource
        .policies
        .write()
        .map_err(|e| (atoms::engine_error(), e.to_string()))?;
    policies.insert(name.clone(), source.clone());

    engine
        .add_policy(name, source)
        .map(|_| ())
        .map_err(|e| (atoms::parse_error(), e.to_string()))
}

#[rustler::nif]
fn native_set_input(
    resource: ResourceArc<EngineResource>,
    json_input: String,
) -> Result<(), (Atom, String)> {
    let mut engine = resource
        .engine
        .write()
        .map_err(|e| (atoms::engine_error(), e.to_string()))?;

    let value: regorus::Value = regorus::Value::from_json_str(&json_input)
        .map_err(|e| (atoms::json_error(), e.to_string()))?;

    engine.set_input(value);

    Ok(())
}

#[rustler::nif]
fn native_add_data(
    resource: ResourceArc<EngineResource>,
    json_data: String,
) -> Result<(), (Atom, String)> {
    let mut engine = resource
        .engine
        .write()
        .map_err(|e| (atoms::engine_error(), e.to_string()))?;

    let value: regorus::Value = regorus::Value::from_json_str(&json_data)
        .map_err(|e| (atoms::json_error(), e.to_string()))?;

    engine
        .add_data(value)
        .map_err(|e| (atoms::engine_error(), e.to_string()))
}

fn value_to_term<'a>(env: Env<'a>, value: regorus::Value) -> Term<'a> {
    match value {
        regorus::Value::Undefined => atoms::undefined().encode(env),
        regorus::Value::Null => rustler::types::atom::nil().encode(env),
        regorus::Value::Bool(b) => b.encode(env),
        regorus::Value::String(s) => s.encode(env),
        regorus::Value::Number(n) => {
            if let Some(i) = n.as_i64() {
                i.encode(env)
            } else if let Some(f) = n.as_f64() {
                f.encode(env)
            } else {
                atoms::undefined().encode(env)
            }
        }
        regorus::Value::Array(arr) => {
            let terms: Vec<Term<'a>> = arr.iter().map(|v| value_to_term(env, v.clone())).collect();
            terms.encode(env)
        }
        regorus::Value::Object(obj) => {
            let pairs: Vec<(Term<'a>, Term<'a>)> = obj
                .iter()
                .map(|(k, v)| {
                    let key: Term<'a> = value_to_term(env, k.clone());
                    let val: Term<'a> = value_to_term(env, v.clone());
                    (key, val)
                })
                .collect();
            Term::map_from_pairs(env, &pairs).unwrap()
        }
        regorus::Value::Set(set) => {
            let terms: Vec<Term<'a>> = set.iter().map(|v| value_to_term(env, v.clone())).collect();
            terms.encode(env)
        }
    }
}

#[rustler::nif]
fn native_eval_query<'a>(
    env: Env<'a>,
    resource: ResourceArc<EngineResource>,
    query: String,
) -> Result<Term<'a>, (Atom, String)> {
    let mut engine = resource
        .engine
        .write()
        .map_err(|e| (atoms::engine_error(), e.to_string()))?;

    let results = engine
        .eval_query(query, false)
        .map_err(|e| (atoms::eval_error(), e.to_string()))?;

    // Return the first result's first expression value, or undefined
    if let Some(result) = results.result.into_iter().next() {
        if let Some(expr) = result.expressions.into_iter().next() {
            return Ok(value_to_term(env, expr.value));
        }
    }

    Ok(atoms::undefined().encode(env))
}

#[rustler::nif]
fn native_get_packages(
    resource: ResourceArc<EngineResource>,
) -> Result<Vec<String>, (Atom, String)> {
    let engine = resource
        .engine
        .read()
        .map_err(|e| (atoms::engine_error(), e.to_string()))?;

    engine
        .get_packages()
        .map_err(|e| (atoms::engine_error(), e.to_string()))
}

#[rustler::nif]
fn native_clear_data(resource: ResourceArc<EngineResource>) -> Result<(), (Atom, String)> {
    let mut engine = resource
        .engine
        .write()
        .map_err(|e| (atoms::engine_error(), e.to_string()))?;

    engine.clear_data();
    Ok(())
}

#[rustler::nif]
fn native_enable_coverage(
    resource: ResourceArc<EngineResource>,
    enable: bool,
) -> Result<(), (Atom, String)> {
    let mut engine = resource
        .engine
        .write()
        .map_err(|e| (atoms::engine_error(), e.to_string()))?;

    engine.set_enable_coverage(enable);
    Ok(())
}

#[rustler::nif]
fn native_get_coverage_report<'a>(
    env: Env<'a>,
    resource: ResourceArc<EngineResource>,
) -> Result<Term<'a>, (Atom, String)> {
    let engine = resource
        .engine
        .read()
        .map_err(|e| (atoms::engine_error(), e.to_string()))?;

    let report = engine
        .get_coverage_report()
        .map_err(|e| (atoms::engine_error(), e.to_string()))?;

    // Convert to Elixir map: %{filename => %{covered: [...], not_covered: [...]}}
    let mut file_reports: Vec<(Term<'a>, Term<'a>)> = Vec::new();

    for file_coverage in report.files.iter() {
        let covered: Vec<i64> = file_coverage.covered.iter().map(|&n| n as i64).collect();
        let not_covered: Vec<i64> = file_coverage.not_covered.iter().map(|&n| n as i64).collect();

        let covered_atom = rustler::Atom::from_str(env, "covered").unwrap();
        let not_covered_atom = rustler::Atom::from_str(env, "not_covered").unwrap();

        let inner_map = Term::map_from_pairs(
            env,
            &[
                (covered_atom.encode(env), covered.encode(env)),
                (not_covered_atom.encode(env), not_covered.encode(env)),
            ],
        )
        .unwrap();

        file_reports.push((file_coverage.path.encode(env), inner_map));
    }

    Ok(Term::map_from_pairs(env, &file_reports).unwrap())
}

#[rustler::nif]
fn native_clear_coverage(resource: ResourceArc<EngineResource>) -> Result<(), (Atom, String)> {
    let mut engine = resource
        .engine
        .write()
        .map_err(|e| (atoms::engine_error(), e.to_string()))?;

    engine.clear_coverage_data();
    Ok(())
}

/// Represents a parsed Rego rule with metadata
#[derive(Debug)]
struct RuleInfo {
    name: String,
    description: String,
    start_line: usize,
    end_line: usize,
}

/// Parse Rego source to extract rule definitions with their metadata
fn parse_rules(source: &str) -> Vec<RuleInfo> {
    let mut rules = Vec::new();
    let lines: Vec<&str> = source.lines().collect();
    let mut pending_comments: Vec<String> = Vec::new();
    let mut i = 0;

    while i < lines.len() {
        let line = lines[i].trim();
        let line_num = i + 1; // 1-indexed

        // Collect comments
        if line.starts_with('#') {
            // Skip section dividers (lines of === or ---)
            let comment_text = line.trim_start_matches('#').trim();
            if !comment_text.chars().all(|c| c == '=' || c == '-' || c.is_whitespace()) {
                pending_comments.push(comment_text.to_string());
            }
            i += 1;
            continue;
        }

        // Skip empty lines but preserve comments
        if line.is_empty() {
            pending_comments.clear();
            i += 1;
            continue;
        }

        // Skip imports and package declarations
        if line.starts_with("import ") || line.starts_with("package ") {
            pending_comments.clear();
            i += 1;
            continue;
        }

        // Try to parse a rule
        if let Some(rule_name) = extract_rule_name(line) {
            let description = pending_comments.last().cloned().unwrap_or_default();
            pending_comments.clear();

            // Find the end of the rule
            let end_line = if line.contains('{') {
                find_rule_end(&lines, i)
            } else {
                line_num // Single-line rule (like `default allow := false`)
            };

            rules.push(RuleInfo {
                name: rule_name,
                description,
                start_line: line_num,
                end_line,
            });

            // Skip to end of rule
            i = end_line;
        } else {
            pending_comments.clear();
            i += 1;
        }
    }

    rules
}

/// Extract the rule name from a line, if it's a rule definition
fn extract_rule_name(line: &str) -> Option<String> {
    let line = line.trim();

    // default name := value
    if line.starts_with("default ") {
        let rest = line.strip_prefix("default ")?.trim();
        let name = rest.split(|c: char| !c.is_alphanumeric() && c != '_')
            .next()?;
        return Some(name.to_string());
    }

    // name := value if { or name if { or name contains value if {
    // Look for pattern: identifier followed by := or contains or if
    let mut chars = line.chars().peekable();
    let mut name = String::new();

    // Extract identifier
    while let Some(&c) = chars.peek() {
        if c.is_alphanumeric() || c == '_' {
            name.push(c);
            chars.next();
        } else {
            break;
        }
    }

    if name.is_empty() {
        return None;
    }

    // Skip whitespace
    while let Some(&c) = chars.peek() {
        if c.is_whitespace() {
            chars.next();
        } else {
            break;
        }
    }

    // Check what follows
    let rest: String = chars.collect();

    if rest.starts_with(":=") || rest.starts_with("=") || rest.starts_with("if ") || rest.starts_with("if{") ||
       rest.starts_with("contains ") {
        Some(name)
    } else {
        None
    }
}

/// Find the end line of a rule by counting braces
fn find_rule_end(lines: &[&str], start_idx: usize) -> usize {
    let mut brace_depth = 0;
    let mut found_open = false;

    for (i, line) in lines.iter().enumerate().skip(start_idx) {
        for c in line.chars() {
            if c == '{' {
                brace_depth += 1;
                found_open = true;
            } else if c == '}' {
                brace_depth -= 1;
            }
        }

        if found_open && brace_depth == 0 {
            return i + 1; // 1-indexed
        }
    }

    // If we never find closing brace, return last line
    lines.len()
}

#[rustler::nif]
fn native_get_rules<'a>(
    env: Env<'a>,
    resource: ResourceArc<EngineResource>,
) -> Result<Term<'a>, (Atom, String)> {
    let policies = resource
        .policies
        .read()
        .map_err(|e| (atoms::engine_error(), e.to_string()))?;

    // Build a map of policy_name => [rules]
    let mut policy_rules: Vec<(Term<'a>, Term<'a>)> = Vec::new();

    for (policy_name, source) in policies.iter() {
        let rules = parse_rules(source);

        let rule_terms: Vec<Term<'a>> = rules
            .iter()
            .map(|rule| {
                let name_atom = rustler::Atom::from_str(env, "name").unwrap();
                let desc_atom = rustler::Atom::from_str(env, "description").unwrap();
                let start_atom = rustler::Atom::from_str(env, "start_line").unwrap();
                let end_atom = rustler::Atom::from_str(env, "end_line").unwrap();

                Term::map_from_pairs(
                    env,
                    &[
                        (name_atom.encode(env), rule.name.encode(env)),
                        (desc_atom.encode(env), rule.description.encode(env)),
                        (start_atom.encode(env), (rule.start_line as i64).encode(env)),
                        (end_atom.encode(env), (rule.end_line as i64).encode(env)),
                    ],
                )
                .unwrap()
            })
            .collect();

        policy_rules.push((policy_name.encode(env), rule_terms.encode(env)));
    }

    Ok(Term::map_from_pairs(env, &policy_rules).unwrap())
}

rustler::init!("Elixir.Regolix.Native");
