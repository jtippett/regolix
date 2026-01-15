use regorus::Engine;
use rustler::{Atom, Encoder, Env, ResourceArc, Term};
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
}

#[rustler::resource_impl]
impl rustler::Resource for EngineResource {}

#[rustler::nif]
fn native_new() -> ResourceArc<EngineResource> {
    ResourceArc::new(EngineResource {
        engine: RwLock::new(Engine::new()),
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

rustler::init!(
    "Elixir.Regolix.Native",
    [
        native_new,
        native_add_policy,
        native_set_input,
        native_add_data,
        native_eval_query,
        native_get_packages
    ]
);
